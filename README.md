# ElasticBeanstalk Restart 

This is a script to setup a lambda function that automatically restarts an Elastic Beanstalk project over a specified interval. 

The script will ask you for your environment name, AWS region, account ID, and Lambda execution role ARN. After providing this information, the script will create the necessary resources and set up the scheduled restarts. The script will pull in your defaul `AWS_PROFILE` if configured. 

Please note that this script assumes you have properly configured the AWS CLI with appropriate credentials and permissions.

# Running The Script

Make sure you're logged in to your AWS account:

```
aws configure
```

Change the script permissions and run the script: 

```
chmod +x ./setup-restart.sh
./setup-restart.sh
```

## Permissions

Make sure your user has `ecr:CreateRepository` and `ecr:GetAuthorizationToken` actions. To resolve these issues, you need to attach a policy with the required permissions to your user.

You can create a custom policy with the required permissions or attach the AWS managed policy `AmazonEC2ContainerRegistryFullAccess` to your user.

## License
 
The MIT License (MIT)

Copyright (c) 2023 Michael Fellows

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.