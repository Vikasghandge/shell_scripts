                                    STEPS TO SETUP LAMBDA FUNCTION TO START AND STOP EC
									
	1) EventBridge (Schedule)
        ↓
     Lambda
        ↓
     EC2 Start / Stop

    2) Note Your EC2 Instance ID 
          example  = Instance ID: i-0fcbf66d4108fe76c
    
    3) Create IAM Role for Lambda Lambda cannot control EC2 without permissions.	
	4) Trusted entity: AWS service  Use case: Lambda Then Click Next
	5) Add Role Name = Lambda-EC2-Start-Stop-Role
    6) Create Inline Policy     Click Create policy → JSON tab → paste this:
	7) Policy name: LambdaEC2StartStopPolicy
-----------	---------------------------------------
	{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
--------------------------------------------
    8) Create Lambda FUNCTION TO Stop Server.
	   Create function --> Author from scratch  --> Function name:stop-jenkins-ec2  Runtime:Python 3.12 Execution Role: Use existing role → Lambda-EC2-Start-Stop-Role
       
	9) Add python Code Replace with Default 

-------------------------------------------------------------------------
import boto3

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    
    instance_id = 'i-0fcbf66d4108fe76c'
    
    ec2.stop_instances(InstanceIds=[instance_id])
    
    return {
        'statusCode': 200,
        'body': 'Jenkins EC2 stopped successfully'
    }


-------------------------------------------------------------------------	
     Click On Deploy 
	 
	 10) Create lambafunction to start the server.
	   function name: start-jenkins-ec2
	   
	   -------------------------------------------------------------------------------
	   import boto3

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    
    instance_id = 'i-0fcbf66d4108fe76c'
    
    ec2.start_instances(InstanceIds=[instance_id])
    
    return {
        'statusCode': 200,
        'body': 'Jenkins EC2 started successfully'
    }
    ----------------------------------------------------------------------------------
	
	
	make sure inside the configuration tab incrase the timeout 3sec to above 10secs
	first of all test it manually is it works or not.
	
	
	11) create eventbridge to stop in the night server.
	
	EventBridge → Rules → Create rule   Name: stop-jenkins-night
	cron expression example --> cron(30 16 * * ? *)



   

	
