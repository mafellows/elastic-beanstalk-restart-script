#!/bin/bash

repository_name="restart-elasticbeanstalk"

get_ecr_inline_policy_document() {
    cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability"
                "ecr:SetRepositoryPolicy",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeImages",
                "ecr:DescribeRepositories",
                "ecr:UploadLayerPart",
                "ecr:ListImages",
                "ecr:InitiateLayerUpload",
                "ecr:GetRepositoryPolicy",
                "ecr:PutImage"
            ],
            "Resource": "arn:aws:ecr:${region}:${account_id}:repository/${repository_name}"
        }
    ]
}
EOF
}


create_lambda_execution_role() {
    lambda_execution_role=$1

    if [[ -z "$lambda_execution_role" ]]; then
        role_name="EBRestartLambdaRole"

        # Check if role already exists
        role_arn=$(aws iam list-roles --query "Roles[?RoleName=='$role_name'].Arn" --output text)
        if [ -z "$role_arn" ]; then
            # Create IAM role and attach policies
            role_arn=$(aws iam create-role --role-name "$role_name" --assume-role-policy-document '{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' --query 'Role.Arn' --output text)

            # Create and attach necessary policies to the Lambda execution role
            aws iam attach-role-policy --role-name "$role_name" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            aws iam attach-role-policy --role-name "$role_name" --policy-arn "arn:aws:iam::aws:policy/AWSElasticBeanstalkFullAccess"

            # Create and attach inline policy for ECR access
            ecr_policy_document=$(get_ecr_inline_policy_document)
            aws iam put-role-policy --role-name "$role_name" --policy-name "EBRestartLambdaECRAccessPolicy" --policy-document "$ecr_policy_document"
        fi
    else
        role_arn=$(aws iam get-role --role-name "$lambda_execution_role" --query 'Role.Arn' --output text)
    fi

    echo "$role_arn"
}


# Function to validate the schedule expression
validate_schedule_expression() {
  if [[ $1 =~ ^([0-9]+)\ (minutes?|hours?|days?)$ ]]; then
    return 0
  else
    return 1
  fi
}

# Get account ID from AWS_PROFILE or default profile
aws_profile="${AWS_PROFILE:-default}"
account_id=$(aws sts get-caller-identity --profile "$aws_profile" --query 'Account' --output text)

echo "Enter your AWS region (default: 'us-east-1'):"
read region
region=${region:-us-east-1}

read -p "Enter your Lambda execution role ARN (or leave blank to create a new role): " user_role_arn
lambda_execution_role_arn=$(create_lambda_execution_role "$user_role_arn")

# List available Elastic Beanstalk environments
echo "Fetching Elastic Beanstalk environments in the selected region..."
environments_list=$(aws elasticbeanstalk describe-environments --no-include-deleted --region "$region" --query 'Environments[].EnvironmentName' --output text)

if [ -z "$environments_list" ]; then
  echo "No Elastic Beanstalk environments found in the selected region."
  exit 1
fi

# Create an array of environment names
IFS=$'\t' read -ra environment_array <<< "$environments_list"

# Display the numbered list of environments
echo "Available Elastic Beanstalk environments:"
for i in "${!environment_array[@]}"; do
  echo "$((i+1)). ${environment_array[i]}"
done
echo ""

# Prompt user to select an environment from the list
while true; do
  echo "Enter the number of the Elastic Beanstalk environment you want to restart:"
  read environment_number

  if [[ $environment_number =~ ^[0-9]+$ ]] && [ $environment_number -ge 1 ] && [ $environment_number -le ${#environment_array[@]} ]; then
    environment_name="${environment_array[$((environment_number-1))]}"
    break
  else
    echo "Invalid number. Please enter a valid number from the list above."
  fi
done

# Get and validate the schedule expression
while true; do
  echo "Enter the schedule expression for the Lambda function (default: '12 hours'):"
  read schedule_expression
  duration=${schedule_expression:-12 hours}
  if validate_schedule_expression "$duration"; then
    schedule_expression="$duration"
    break
  else
    echo "Invalid schedule expression. Please enter a valid expression, e.g., '5 minutes', '2 hours', '1 day'."
  fi
done

# Get and validate Lambda timeout
while true; do
  echo "Enter the Lambda function timeout in seconds (minimum: 1, maximum: 900, default: 60):"
  read lambda_timeout
  lambda_timeout=${lambda_timeout:-60}

  if [[ $lambda_timeout =~ ^[1-9][0-9]*$ ]] && [ $lambda_timeout -ge 1 ] && [ $lambda_timeout -le 900 ]; then
    break
  else
    echo "Invalid Lambda timeout. Please enter a valid timeout between 1 and 900 seconds."
  fi
done

# Create the script to restart Elastic Beanstalk environment
cat > restart-environment.sh << EOF
#!/bin/bash

set -e

ENVIRONMENT_NAME="$environment_name"
REGION="$region"

aws elasticbeanstalk restart-app-server --environment-name \$ENVIRONMENT_NAME --region \$REGION
EOF

# Make the script executable
chmod +x restart-environment.sh

# Create the Lambda function package    
mkdir -p lambda_function
cp restart-environment.sh lambda_function

cat > lambda_function/Dockerfile << EOF
FROM amazon/aws-cli:latest

COPY restart-environment.sh /restart-environment.sh

ENTRYPOINT ["/bin/bash", "/restart-environment.sh"]
EOF

# Build, tag, and push the Docker image
cd lambda_function
docker build -t restart-elasticbeanstalk .
aws ecr create-repository --repository-name restart-elasticbeanstalk --region $region
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $account_id.dkr.ecr.$region.amazonaws.com
docker tag restart-elasticbeanstalk:latest $account_id.dkr.ecr.$region.amazonaws.com/restart-elasticbeanstalk:latest
docker push $account_id.dkr.ecr.$region.amazonaws.com/restart-elasticbeanstalk:latest
cd ..


# Create the Lambda function
echo "Creating the lambda function..."
echo "account_id: $account_id"
echo "region: $region"
echo "lambda_execution_role_arn: $lambda_execution_role_arn"
echo "lambda_timeout: $lambda_timeout"

aws lambda create-function \
    --function-name restart-elasticbeanstalk \
    --package-type Image \
    --code ImageUri=$account_id.dkr.ecr.$region.amazonaws.com/restart-elasticbeanstalk:latest \
    --role $lambda_execution_role_arn \
    --timeout $lambda_timeout \
    --region $region

# Create the Amazon EventBridge rule and add the Lambda function as a target
aws events put-rule \
    --name "RestartElasticBeanstalk" \
    --schedule-expression "rate($schedule_expression)" \
    --region $region

aws events put-targets \
    --rule "RestartElasticBeanstalk" \
    --targets "Id"="1","Arn"="arn:aws:lambda:$region:$account_id:function:restart-elasticbeanstalk" \
    --region $region

echo "Setup complete. Elastic Beanstalk environment will restart every $schedule_expression."