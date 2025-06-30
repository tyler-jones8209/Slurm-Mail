#!/bin/bash

# Written by yours truly, Tyler Jones.

echo "Debug: Script started" >> /tmp/slurm-mail-debug.log

# pull information passed when job is queued
INPUT="$2"

# extract variables from scontrol show job command
JOB_ID=$(echo "$INPUT" | grep -oP 'Job_id=\K\d+')
JOB_NAME=$(scontrol show job "$JOB_ID" | grep -oP 'JobName=\K.*')
USER_ID=$(scontrol show job "$JOB_ID" | grep -oP 'UserId=\K\w+')
JOB_STATE=$(scontrol show job "$JOB_ID" | grep -oP 'JobState=\K\w+')
PARTITION=$(scontrol show job "$JOB_ID" | grep -oP 'Partition=\K\w+')
NODE_LIST=$(scontrol show job "$JOB_ID" | grep -oP '^.*NodeList=\K\S+' | grep -v "(null)")
NODES=$(scontrol show job "$JOB_ID" | grep -oP 'NumNodes=\K\d+')
CORES=$(scontrol show job "$JOB_ID" | grep -oP 'NumCPUs=\K\d+')
TASKS=$(scontrol show job "$JOB_ID" | grep -oP 'NumTasks=\K\d+' || echo "N/A")
CORE_TASKS=$(scontrol show job "$JOB_ID" | grep -oP 'CPUs/Task=\K\d+')
EMAIL=$(scontrol show job "$JOB_ID" | grep -oP 'MailUser=\K[^\s]+')
SUBMIT_DATE=$(scontrol show job "$JOB_ID" | grep -oP 'SubmitTime=\K[^T]+')
SUBMIT_TIME=$(scontrol show job "$JOB_ID" | grep -oP 'SubmitTime=\K[^T]*T\K\d{2}:\d{2}:\d{2}')
START_DATE=$(scontrol show job "$JOB_ID" | grep -oP 'StartTime=\K[^T]+' || echo "Unknown")
START_TIME=$(scontrol show job "$JOB_ID" | grep -oP 'StartTime=\K[^T]*T\K\d{2}:\d{2}:\d{2}' || echo "Unknown")
END_DATE=$(scontrol show job "$JOB_ID" | grep -oP 'EndTime=\K[^T]+' || echo "Unknown")
END_TIME=$(scontrol show job "$JOB_ID" | grep -oP 'EndTime=\K[^T]*T\K\d{2}:\d{2}:\d{2}' || echo "Unknown")
RUN_TIME=$(scontrol show job "$JOB_ID" | grep -oP 'RunTime=\K\d{2}:\d{2}:\d{2}+' || echo "Unknown")
FAIL_REASON=$(scontrol show job "$JOB_ID" | grep -oP 'Reason=\K\w+' || echo "Unknown")
MAIL_TYPE=$(scontrol show job "$JOB_ID" | grep -oP 'MailType=\K.*')

# check if user specifies mail user in sbatch file otherwise, exit
if [ -n "$EMAIL" ]; then

contains_type() {
    local list="$1"
    local type="$2"
    [[ ",${list}," == *",${type},"* ]]
}

# email details
TO=$EMAIL
FROM="Faraday Slurm Scheduler <slurm@faraday.cluster.earlham.edu>"
SUBJECT="Job: ${JOB_NAME} (#${JOB_ID}) is ${JOB_STATE}"

if contains_type "$MAIL_TYPE" "FAIL" && [ "$JOB_STATE" = "FAILED" ]; then
  EMAIL_BODY=$(cat <<EOF
From: $FROM
To: $TO
Subject: $SUBJECT

Super not a success! Your job has successfully failed unsuccessfully.

FAIL
----
Failure Reason: $FAIL_REASON

USER INFORMATION
----------------
User ID: $USER_ID
Email: $EMAIL

JOB INFORMATION
---------------
Job Name: $JOB_NAME
Job ID: $JOB_ID
Job State: $JOB_STATE
Partition: $PARTITION
Requested Nodes: $NODES
Requested Cores: $CORES
Requested Tasks: $TASKS
Requested Cores/Task: $CORE_TASKS

EOF
)

# create email for when job is running
elif contains_type "$MAIL_TYPE" "BEGIN" && [ "$JOB_STATE" = "RUNNING" ]; then
  EMAIL_BODY=$(cat <<EOF
From: $FROM
To: $TO
Subject: $SUBJECT

Success! Your job has started successfully.

USER INFORMATION
----------------
User ID: $USER_ID
Email: $EMAIL

JOB INFORMATION
---------------
Job Name: $JOB_NAME
Job ID: $JOB_ID
Job State: $JOB_STATE
Partition: $PARTITION
Requested Nodes: $NODES
Requested Cores: $CORES
Requested Tasks: $TASKS
Requested Cores/Task: $CORE_TASKS

SUBMIT
------
Submit Date: $SUBMIT_DATE
Submit Time: $SUBMIT_TIME

START
-----
Start Date: $START_DATE
Start Time: $START_TIME

EOF
)

# create email for when job is complete
elif contains_type "$MAIL_TYPE" "END" && [ "$JOB_STATE" = "COMPLETED" ]; then
  # Create email body for COMPLETED state
  EMAIL_BODY=$(cat <<EOF
From: $FROM
To: $TO
Subject: $SUBJECT

Even bigger success! Your job has completed successfully.

USER INFORMATION
----------------
User ID: $USER_ID
Email: $EMAIL

JOB INFORMATION
---------------
Job Name: $JOB_NAME
Job ID: $JOB_ID
Job State: $JOB_STATE
Partition: $PARTITION
Nodes Used: $NODE_LIST
Requested Nodes: $NODES
Requested Cores: $CORES
Requested Tasks: $TASKS
Requested Cores/Task: $CORE_TASKS

SUBMIT
------
Submit Date: $SUBMIT_DATE
Submit Time: $SUBMIT_TIME

START
-----
Start Date: $START_DATE
Start Time: $START_TIME

END
---
End Date: $END_DATE
End Time: $END_TIME
Run Time: $RUN_TIME
EOF
)

# create email when job is pending
elif [ "$JOB_STATE" = "CANCELLED" ]; then
  EMAIL_BODY=$(cat <<EOF
From: $FROM
To: $TO
Subject: $SUBJECT

Not a success! Your job was cancelled successfully.

FAIL
----
Failure Reason: $FAIL_REASON

USER INFORMATION
----------------
User ID: $USER_ID
Email: $EMAIL

JOB INFORMATION
---------------
Job Name: $JOB_NAME
Job ID: $JOB_ID
Job State: $JOB_STATE
Partition: $PARTITION
Requested Nodes: $NODES
Requested Cores: $CORES
Requested Tasks: $TASKS
Requested Cores/Task: $CORE_TASKS

EOF
)

else
  echo "Unknown state for Job ID: $JOB_ID" > /tmp/slurm-mail-error.log
  exit 1
fi

else
  echo "MailUser not specified. Exiting Slurm Mail."
  exit 0

fi

echo "$EMAIL_BODY" > /tmp/slurm-mail-email-$JOB_ID.log

echo "$EMAIL_BODY" | /usr/sbin/sendmail -t
