REGION=eu-west-1

KEY_NAME="cloud-course-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"
echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME | jq -r ".KeyMaterial" > $KEY_PEM
chmod 400 $KEY_PEM

VPC_ID=$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true | jq -r .Subnets[0] | jq -r .VpcId)
VPC_CIDR_BLOCK=$(aws ec2 describe-vpcs --filters Name=vpc-id,Values=$VPC_ID | jq -r .Vpcs[0].CidrBlock)
echo "VPCs IDs: $VPC_ID"

MY_IP=$(curl ipinfo.io/ip)
STACK_NAME="my-stack"
STACK_RES=$(aws cloudformation create-stack --stack-name $STACK_NAME --template-body file://cloudformation.yml --capabilities CAPABILITY_NAMED_IAM \
	--parameters ParameterKey=InstanceType,ParameterValue=t2.micro \
	ParameterKey=KeyName,ParameterValue=$KEY_NAME \
	ParameterKey=SSHLocation,ParameterValue=$MY_IP/32 \
	ParameterKey=VPCcidr,ParameterValue=$VPC_CIDR_BLOCK)
STACK_ID=$(echo $STACK_RES | jq -r '.StackId')
echo "Creating $STACK_ID"
aws cloudformation wait stack-create-complete --stack-name $STACK_ID

# get the wanted stack
STACK=$(aws cloudformation --region $REGION describe-stacks --stack-name $STACK_NAME | jq -r .Stacks[0])
OUTPUTS=$(echo $STACK | jq -r .Outputs)
echo "Stack outpust: $OUTPUTS"

echo "getting instances IP"
PUBLIC_IP_1=$(aws cloudformation --region $REGION describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='Instance1IP'].OutputValue" --output text)
PRIVATE_IP_1=$(aws cloudformation --region $REGION describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='Instance1PrivateIp'].OutputValue" --output text)
PUBLIC_IP_2=$(aws cloudformation --region $REGION describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='Instance2IP'].OutputValue" --output text)
PRIVATE_IP_2=$(aws cloudformation --region $REGION describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='Instance2PrivateIp'].OutputValue" --output text)
INSTANCE_ID_1=$(aws cloudformation --region $REGION describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='InstanceId1'].OutputValue" --output text)
INSTANCE_ID_2=$(aws cloudformation --region $REGION describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='InstanceId2'].OutputValue" --output text)
SG_FOR_WORKERS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID_1 --query 'Reservations[*].Instances[*].[SecurityGroups[].GroupId |[*]]' --output text)

echo "Instance #1 ID - $INSTANCE_ID_1"
echo "Instance #1 public IP - $PUBLIC_IP_1"
echo "Instance #1 private IP - $PRIVATE_IP_1"
echo "Instance #2 ID - $INSTANCE_ID_2"
echo "Instance #2 public IP - $PUBLIC_IP_2"
echo "Instance #2 private IP - $PRIVATE_IP_2"

sleep 240
echo "Code on the 1st instance"
# 1
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_1<<EOF
	sudo apt-get --purge remove redis-server -y
	sudo rm -rf /etc/redis/dump.rdb
	sudo apt-get update
	sudo apt-get install redis-server -y
	sudo mv cc-ophir-idan-niv-hw2/redis.conf /etc/redis/redis.conf
	sudo nohup python3 /home/ubuntu/cc-ophir-idan-niv-hw2/main.py $PRIVATE_IP_2 $KEY_NAME $SG_FOR_WORKERS $PRIVATE_IP_1 > /dev/null 2>&1 &
	sudo /usr/bin/redis-server /etc/redis/redis.conf
	nohup flask run --host 0.0.0.0  &>/dev/null &
	exit
EOF
# 2
echo "Code on the 2nd instance"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_2<<EOF
	sudo apt-get --purge remove redis-server -y
	sudo rm -rf /etc/redis/dump.rdb
	sudo apt-get update
	sudo apt-get install redis-server -y
	sudo mv cc-ophir-idan-niv-hw2/redis.conf /etc/redis/redis.conf
	sudo nohup python3 /home/ubuntu/cc-ophir-idan-niv-hw2/main.py $PRIVATE_IP_1 $KEY_NAME $SG_FOR_WORKERS $PRIVATE_IP_2 > /dev/null 2>&1 &
	sudo /usr/bin/redis-server /etc/redis/redis.conf
	nohup flask run --host 0.0.0.0  &>/dev/null &
	exit
EOF

echo "done"

