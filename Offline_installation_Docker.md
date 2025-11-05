## ✅ Step-by-Step Offline Setup Plan

(A) Download all necessary packages

We’ll prepare Docker binaries and Docker Compose manually.

1) Create a working folder:
```
mkdir docker-offline
cd docker-offline

```

2) Download Docker binaries:

```
wget https://download.docker.com/linux/static/stable/x86_64/docker-27.1.1.tgz
tar xzvf docker-27.1.1.tgz

```

3) Download Docker Compose binary:
```
curl -L "https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-x86_64" -o docker-compose
chmod +x docker-compose
```

## optional step for example 
```
docker pull mysql:8.0
docker pull ghandgevikas/leave-management:latest

docker save -o mysql_8.tar mysql:8.0
docker save -o leave_management.tar ghandgevikas/leave-management:latest

```

4) Now your docker-offline folder should contain:
docker/
docker-compose
mysql_8.tar
leave_management.tar


5) Then from Bastion → Private server:
SSH into the bastion and run:

```
scp -i aws.pem -r /home/ubuntu/docker-offline ubuntu@10.10.2.254:/home/ubuntu/

```

## STEP 3️⃣: On the private EC2 (offline server)
(A) Install Docker manually

```
cd /home/ubuntu/docker-offline
sudo cp docker/* /usr/bin/
sudo dockerd &
docker version
```


(B) Install Docker Compose

```
sudo cp docker-compose /usr/local/bin/
sudo chmod +x /usr/local/bin/docker-compose
docker-compose version

```

6) command to load preload images 
```
sudo docker load -i mysql_8.tar
sudo docker load -i leave_management.tar

```

STEP 5️⃣: Deploy your app

```
cd /home/ubuntu/docker-offline
sudo docker-compose up -d

```



