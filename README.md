## Packer img-mgr lab

For this exercise we will continue working with the img-mgr application. This time around we are going to use it to extend what we've learned with `packer` to create an immutable AMI of the application.

### Immutable servers solve the following issues taken from [here](https://aws.amazon.com/blogs/mt/create-immutable-servers-using-ec2-image-builder-aws-codepipeline/):

Here are some (fictional) examples of production incidents related to unintended differences between EC2 instances:

1.  “Four weeks ago, we inadvertently pushed a configuration file to the wrong server. It went unnoticed until yesterday, when the server was rebooted and our application did not start. It took us three hours to restore service because we initially only considered yesterday’s changes as a likely cause of the issue.”
2.  “Last week, the infrastructure team tightened network security policies. Yesterday’s sales campaign brought more traffic to the website, which meant we needed to create new EC2 instances. On startup, the instances tried to connect to an external Yum repository to install a runtime but could not reach it. The new capacity didn’t come online and the existing instances collapsed under the increased load. It took time to identify the network as the root cause. We lost hours of revenue at a crucial time for our Sales and Marketing department.”
3.  “We had a strange issue in production but were unable to reproduce it in our QA environment. For testing purposes, the QA team had recently updated the environment to run the next version of the software. Despite our best efforts, we cannot ascertain that QA is 100 percent equal to production. We hope the issue will disappear after Monday’s go-live.”

Each of these incidents is related to differences between EC2 instances. In the first example, one instance is misconfigured due to human error. In the second example, the difference is that the new instances do not have the software installed yet. External installation dependencies during system startup increase the risk of failure and slow down the startup. In the third example, there is no mechanism to reproduce an exact replica of production.

Immutable servers can help prevent these issues. When you treat instances as immutable, they will always be exact replicas of their AMI. This leads to integrity and reproducibility of the instance. When you ship fully installed AMIs, you have no more installation dependencies on startup, so there is no more risk of installations failing at the worst possible time. Shipping fully installed AMIs also reduces the time it takes to add capacity to your fleet because you don’t have to wait for the installation to finish.

It’s not a silver bullet, though. For example, the root cause of the third issue might be outside the EC2 instance. It might have originated in the data store or in an underlying service. From the example, you can’t tell with certainty. With an immutable server, though, you can at least rule out differences between EC2 instances as a suspect.

## Creating a packer AMI of our img-mgr

Provided within this repo is a `Makefile` that contains the directive to run `packer` against the provided config file `img-mgr-packer.json` within the `packer/` folder. Run this to generate an AMI within the `us-west-2` region.

## Create infra

Launch the `vpc.cfn` and `img-mgr.cfn` runway modules from within the `runway/` folder.

## New version of the application

Within github fork the repo https://github.com/dianephan/flask-aws-storage on over into your personal github account. Make a change to it to uniquely identify that this is a new version of the app.

Update `install_my_app.sh` to your forked version of the `flask-aws-storage`. Once you've done so, create a new AMI based on your latest version.

Now role out your version of your application by updating the runway project `dev-us-west-2.env` file to point to your ami as env var `ami_id`. Invoke runway for the `dev` env. Watch it roll out.

## Stash the AMI ID in Parameter Store

Create a new clear text string parameter store key named `/common/img-mgr/golden-ami` and populate the value of your new AMI with it. I have updated this repo to make reference to it within the stacker lookup.

## Jenkins build server set up

Deploy the `jenkins.cfn` module. Initialize the Jenkins server by installing the recommended plugins after grabbing the administrator password off of the disk of the server. You can use an SSM Session to gain access to the credentials file. You can then access the Jenkins server at its public IP address in your web browser using TCP port 8080.

## Jenkins packer AMI build job

Create a new `Freestyle` job named `packer-build` and within it configure it as a `git` source code project. Give it this TOP docs repo `git@bitbucket.org:corpinfo/top-training-material.git` as the repo. Create a Jenkins secret type of `SSH Username with private key` enter your *private* key that is used to access bitbucket. In a customer environment we would create a deploy key with limited access, but for this exercise this will do.

Set this up as a parameterized project, add `FLASK_REPO` as a string parameter with the value of your https git end point for your customized flask app.

Add an `Execute Shell` build step as part of this job with the following contents

```
cd packer-shell/packer/
make
REGION=$(curl -q http://169.254.169.254/latest/meta-data/placement/region)
IMG_MGR_AMI=$(cat packer-output.log | grep ^us-|sed s/"^.*: "//)
aws --region $REGION ssm put-parameter \
    --name "/common/img-mgr/golden-ami" \
    --type "String" \
    --value $IMG_MGR_AMI \
    --overwrite
```

Save.

## Deploy job

Create another `Freestyle project` named `infra-deploy` but this time, scroll down on this screen and use the `Copy from` form to type in `packer-build`

Update the `Execute Shell` build step with the following contents
```
cd packer-shell/runway
cat > runway.yml << EOF
---
# See full syntax at https://docs.onica.com/projects/runway/en/latest/
deployments:
  - modules:
      - path: img-mgr.cfn
        parameters:
          account_id: \${env ACCOUNT_ID}
    regions:
      - us-west-2
EOF
./deploy.sh
```

Save.

## Job chaining

Return back to the `packer-build` job and add a `post-build action` to `Build other projects`. Set the downstream job to the `infra-deploy` job.

Now kick off the `packer-build` job and keep an eye on your infrastructure.
