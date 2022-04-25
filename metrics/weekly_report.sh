#! /bin/bash

# this is currently running on Windows Subsystem Linux and sometimes mail is flakey
# sudo service postfix status may be needed 
# migrated it to run in ssc-vm but now it looks like cron doesn't load the env var I need

# this is probably not the right way to do this but manually source the .bashrc
. ~/.bashrc


# this only works for some dumb reason if you're calling the script with the full path
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

mail_verbose_prefix="Weekly CORTX Verbose Reports"
mail_scrape_prefix="Weekly CORTX Scraping"
mail_subj_prefix="Weekly CORTX Community Report"
#mail_subj_prefix="TESTING COMMUNITY METRICS" # use this for testing
Email="john.bent@seagate.com"
server=gtx201.nrm.minn.seagate.com
summary=$(mktemp /tmp/scrape.XXXXXXXXX)
touch $summary

# start with a git pull in case things were updated elsewhere
git pull

# use command line to control what runs.  By default, both the scrape and the report happen.
scrape=1
report=1
if [ "$1" == "noscrape" ]; then
  scrape=0
elif [ "$1" == "noreport" ]; then
  report=0
fi

function run_command {
  Command=$1
  subject=$2
  Email=$3
  echo "Command $Command , subj $subject , email $Email"
  tfile=$(mktemp /tmp/cortx_community.XXXXXXXXX.txt)
  $Command &> $tfile
  ret=$?
  mail -s "$subject" -r $Email $Email < $tfile
  echo "RET $ret from $Command" >> $summary
}

function group_activity {
  group=$1
  gname=$2
  tfile=$(mktemp /tmp/cortx_community.XXXXXXXXX)
  ./get_personal_activity.py "$group" -w > $tfile
  mail -s "$mail_verbose_prefix - $gname Activity" -r $Email $Email < $tfile
}

function scp_report {
  report=$1
  directory=$2
  src=`ls /tmp/$report*html`
  ts=`date +%Y-%m-%d`
  base=`basename $src .html`
  src2=/tmp/$base.$ts.html
  scp $src 535110@$server:/home/535110/public_html/latest
  cp $src $src2 
  scp $src2 535110@$server:/home/535110/public_html/$directory
}

if [ $scrape == 1 ]; then
  echo "Doing scrape"
  run_command "./scrape_slack.py" "$mail_scrape_prefix - Slack" $Email
  run_command "./scrape_projects.py -v" "$mail_scrape_prefix - Projects" $Email
  run_command "./scrape_metrics.py CORTX" "$mail_scrape_prefix - Github" $Email
  for p in 'Ceph' 'MinIO' 'DAOS' 'Swift' 'OpenIO' 'ECS'
  do
    run_command "./scrape_metrics.py -t $p" "$mail_scrape_prefix - $p Github" $Email
  done

  mail -s "$mail_scrape_prefix - Summary" -r $Email $Email < $summary
fi

if [ $report == 1 ]; then 
  echo "Doing report"
  ts=`date +%Y-%m-%d`

  # create and send the partnership report
  echo "Creating partnership review"
  partnership_report=CORTX_Community_Partnerships_Review
  ./mk_community_partnership_report.py 
  ts=`date +%Y-%m-%d`
  scp ${partnership_report}.pdf 535110@$server:/home/535110/public_html/latest
  scp ${partnership_report}.pdf 535110@$server:/home/535110/public_html/community_partnerships/$partnership_report.$ts.pdf
  echo "CORTX Partnership Review attached" | mail -s "CORTX Partnerships - Please Update Status (see attached)" -r $Email -a $partnership_report.pdf $Email 

  # mail activity reports
  for group in 'EU R&D' Innersource External Unknown
  do
    group_activity "$group" "$group"
  done
  group_activity 'johnbent,justinzw,r-wambui,hessio,swatid-seagate,novium258,mukul-seagate11,mmukul' 'Open Source Team'
  group_activity 'rajkumarpatel2602,shraddhaghatol,priyanka25081999,huanghua78,mbcortx,trshaffer' 'ADG'

  jupyter_args="--ExecutePreprocessor.timeout=1800 --output-dir=/tmp --no-input"

  /bin/rm -rf /tmp/CORTX_Metrics_* # clean up any old crap

  exec_report=CORTX_Metrics_Topline_Report
  jupyter nbconvert --execute --to slides --SlidesExporter.reveal_theme=serif --SlidesExporter.reveal_scroll=True $jupyter_args --output $exec_report $exec_report.ipynb
  scp_report $exec_report exec_reports

  cc_report=CORTX_Metrics_Community_Activity
  jupyter nbconvert --execute --to html $jupyter_args --output $cc_report $cc_report.ipynb
  scp_report $cc_report community_reports

  bulk_report=CORTX_Metrics_Graphs
  jupyter nbconvert --execute --to html $jupyter_args --output $bulk_report $bulk_report.ipynb
  scp_report $bulk_report bulk_graphs

  health_report=Repo_Health
  jupyter nbconvert --execute --to html $jupyter_args --output $health_report $health_report.ipynb
  scp_report $health_report health_reports
  python3 ./html_to_pdf.py
  echo "CORTX Repository Health Report Attached" | mail -s "CORTX Repository Health Report" -r $Email -a cache/repo_health.pdf $Email 

  compare_report=CORTX_Metrics_Compare_Projects
  jupyter nbconvert --execute --to html $jupyter_args --output $compare_report $compare_report.ipynb
  scp_report $compare_report compare_projects
  
  # mail the metrics as a CSV 
  tfile="/tmp/cortx_community_stats.$ts.csv"
  tfile2="/tmp/cortx_community_stats.$ts.txt"
  printf "Weekly autogenerated reports are available at http://gtx201.nrm.minn.seagate.com/~535110/.  Enjoy!\n\nSummary Stats Also Below and attached as CSV.\n" > $tfile2
  ./print_metrics.py -c -a -s | grep -v '^Statistics' > $tfile
  ./print_metrics.py >> $tfile2
  mail -s "$mail_subj_prefix - Report Available Plus Summary plus Attached CSV" -r $Email -a $tfile $Email < $tfile2

fi

./commit_pickles.sh | mail -s "Weekly Pickle Commit for CORTX Community" -r $Email $Email


exit
