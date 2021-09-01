#!/bin/ksh
#***************************************************************************/
#*                                                                         */
#* Filename    : api-hourlyreport.sh                                       */
#*                                                                         */
#* Description : Hourly monitoring report of API api by generating csv     */
#*              files from logs and sending report in html format          */
#*                                                                         */
#*                                                                         */
#*                                                                         */
#* Parameters  : None                                                      */
#*                                                                         */
#* Created By  : Ibrahim Patel                                             */
#*                                                                         */
#* Modification History                                                    */
#*                                                                         */
#* Version Date     TPR/CR     Author Description                          */
#* 1.0     06/07/2021            TR     Initial Build                      */
#***************************************************************************/

export DATE=`date '+%d'`"-"`date '+%b'`"-"`date '+%Y'`
LOGPATH="/software/bea/apache-tomcat-voip/logs"
SCRIPT_HOME="/software/bea/API-REPORT"
LOGFILE="$LOGPATH/APIaccessservice.log"
MESSAGE="$SCRIPT_HOME/hourly-log.txt"
REPORT_HTML="$SCRIPT_HOME/APIreport.html"
rm -f $SCRIPT_HOME/*.csv;
rm -f $REPORT_HTML

current_hour=`date +'%H'`
report_hr=`expr $current_hour - 1`

if [ $report_hr -le 9 ]
then
        report_hr=0$report_hr
fi

### $MESSAGE variable stores the hourly report ###

grep "^$report_hr" $LOGFILE > $MESSAGE

### report.csv file is created from above created hourly log by fetching the APIs which have both Starts and Ends matching, and 2 more columns are created holding the Starts matching time
### and Ends matching time ####

apilist="$SCRIPT_HOME/apilist_type.txt"
cut -d ',' -f1 $apilist | while read line
do
        API=$(egrep `echo $line` $MESSAGE|egrep "Starts|Ends"|sed -n -e '/Ends/h' -e '/Starts/{x;G;p}'|sed -n -e '/Starts/h' -e '/Ends/{x;G;p}'|grep "Starts"|awk '{print $6}'|tr -d "()"| tr -d -)
        API_START_TIME=$(egrep `echo $line` $MESSAGE|egrep "Starts|Ends"|sed -n -e '/Ends/h' -e '/Starts/{x;G;p}'|sed -n -e '/Starts/h' -e '/Ends/{x;G;p}'|grep "Starts"|awk '{print $1}')
        API_END_TIME=$(egrep `echo $line` $MESSAGE|egrep "Starts|Ends"|sed -n -e '/Ends/h' -e '/Starts/{x;G;p}'|sed -n -e '/Starts/h' -e '/Ends/{x;G;p}'|grep "Ends"|awk '{print $1}')
        paste -d, <(echo "$API") <(echo "$API_START_TIME") <(echo "$API_END_TIME") >> $SCRIPT_HOME/report.csv;
done

### Using above created report.csv another csv file report1.csv is created to convert the columns to date format and calculate the time difference ###

while read line
do
        echo $line;
        CSV_API=$(echo $line | cut -d "," -f1)
        CSV_START_TIME=$(echo $line | cut -d "," -f2);
        CSV_END_TIME=$(echo $line | cut -d "," -f3);
        START_TIME=$(date -d "$CSV_START_TIME" '+%s.%3N');
        END_TIME=$(date -d "$CSV_END_TIME" '+%s.%3N');
        TIME_DIFF=(($(echo "$END_TIME - $START_TIME" | bc)) * 1000);
        TOTAL_TIME=$(($TIME_DIFF * 1000));
        paste -d, <(echo "$CSV_API") <(echo "$CSV_START_TIME") <(echo "$CSV_END_TIME") <(echo "$TOTAL_TIME") >> $SCRIPT_HOME/report1.csv;
done < $SCRIPT_HOME/report.csv

### Using above created report1.csv, another csv file is created report2.csv to calculate the success,failed, minimum time, maximum time and average time ###

for item in `cut -d , -f 1 $SCRIPT_HOME/report1.csv | sort | uniq |sed 1d`
do
        API_NAMES=$(awk -F"," '{print $1}' $SCRIPT_HOME/report1.csv |sort|uniq | sed 1d |grep `echo $item`)
        TOTAL=$(egrep `echo $item` $MESSAGE|egrep "Starts|Ends"|grep "Starts"|wc -l)
        SUCCESS=$(egrep `echo $item` $SCRIPT_HOME/report1.csv | sort | uniq -c|wc -l)
        FAILURE=`expr $TOTAL - $SUCCESS`
        MIN=$(grep $item $SCRIPT_HOME/report1.csv | sort -n -t , -k 4 | awk -F , '{print $4}' | head -n 1)
        MAX=$(grep $item $SCRIPT_HOME/report1.csv | sort -n -t , -k 4 | awk -F , '{print $4}' | tail -n 1)
        AVG=$(grep $item $SCRIPT_HOME/report1.csv | sort -n -t , -k 4 |awk -F',' '{ sum += $4 } END { print(sum / NR) }')
        paste -d, <(echo "$API_NAMES") <(echo "$TOTAL") <(echo "$SUCCESS") <(echo "$FAILURE") <(echo "$MIN") <(echo "$MAX") <(echo "$AVG") >> $SCRIPT_HOME/report2.csv;
done

### Below csv file is created to get details of all APIs with all failure hits ###

while read line
do
        E_API_NAMES=$(egrep `echo $line` $MESSAGE|egrep "Starts|Ends"|awk '!/Starts/{next} NR == nl && $NF!="Ends" {print p} $NF=="Starts" {p=$0; nl=NR+1}'|awk '{print $6}'| tr -d -|sort|uniq)
        E_TOTAL=$(egrep `echo $line` $MESSAGE|egrep "Starts|Ends"|awk '!/Starts/{next} NR == nl && $NF!="Ends" {print p} $NF=="Starts" {p=$0; nl=NR+1}'|awk '{print $6}'| tr -d - |wc -l)
        E_SUCCESS=0
        E_FAILURE=`expr $E_TOTAL - $E_SUCCESS`
        E_MIN=0
        E_MAX=0
        E_AVG=0
        paste -d, <(echo "$E_API_NAMES") <(echo "$E_TOTAL") <(echo "$E_SUCCESS") <(echo "$E_FAILURE") <(echo "$E_MIN") <(echo "$E_MAX") <(echo "$E_AVG") >> $SCRIPT_HOME/all_errored.csv;
done < $apilist

### Finally report2.csv and all_errored.csv files are merged using below command to print the html report ###
if [ -f $SCRIPT_HOME/report2.csv ]
    then
        awk -F, 'FNR==NR {a[$1];print;next} !($1 in a)' $SCRIPT_HOME/report2.csv $SCRIPT_HOME/all_errored.csv | grep -v ",0,0,0,0,0,0" > $SCRIPT_HOME/total-report.csv
fi
### CreateReport funtion is use to generate html report from the above created html-report.csv
if [ -f $SCRIPT_HOME/total-report.csv ]
    then
awk -F, 'BEGIN {FS = OFS = ","}NR==FNR { n[$1]=$0;next } ($1 in n) { print n[$1],$2,$3 }' $SCRIPT_HOME/total-report.csv $SCRIPT_HOME/apilist_type.txt > $SCRIPT_HOME/html-report.csv
fi

CreateReport()
{
  echo "<html><body>Hi All,<br><br>Please find below report for API ACCESS API Journeys :<br><br><table border=\"1\" width=\"80%\"><tr bgcolor=\"#a9cce3\">
    <th>CLASS</th><th>API</th><th>TYPE</th><th>REQUEST COUNT</th><th>SUCCESS COUNT</th><th>FAILED COUNT</th><th>MIN RESPONSE TIME(in ms)</th><th>MAX RESPONSE TIME(in ms)</th><th>AVG RESPONSE TIME(in ms)</th><th>THRESHOLD TIME(in ms)</th>" > $REPORT_HTML
    if [ -f $SCRIPT_HOME/html-report.csv ]
    then
        while read line
        do
           echo $line;
           CLASS=$(echo $line | cut -d "." -f1);
           API=$(echo $line | cut -d "." -f2 | cut -d "," -f1);
           TYPE=$(echo $line | cut -d "," -f8);
           TOTAL=$(echo $line | cut -d "," -f2);
           SUCCESS=$(echo $line | cut -d "," -f3);
           FAILED=$(echo $line | cut -d "," -f4);
           MIN=$(echo $line | cut -d "," -f5);
           MAX=$(echo $line | cut -d "," -f6);
           AVG=$(echo $line | cut -d "," -f7);
           THRESHOLD=$(echo $line | cut -d "," -f9);
           echo "CLASS : $CLASS , API : $API , TYPE : $TYPE , TOTAL : $TOTAL , SUCCESS : $SUCCESS , FAILED : $FAILED , MIN : $MIN, MAX : $MAX, AVG : $AVG, THRESHOLD : $THRESHOLD"
           echo "<tr><td align=\"center\">$CLASS</td><td align=\"center\">$API</td><td align=\"center\">$TYPE</td><td align=\"center\">$TOTAL</td><td align=\"center\">$SUCCESS</td><td align=\"center\">$FAILED</td><td align=\"center\">$MIN</td><td align=\"center\">$MAX</td><td align=\"center\">$AVG</td><td align=\"center\">$THRESHOLD</td></tr>" >> $REPORT_HTML
           line="";
        done < $SCRIPT_HOME/html-report.csv
        echo "</table><br><br>" >> $REPORT_HTML
    fi
}

CreateReport;

if [ -f $SCRIPT_HOME/total-report.csv ]
then
MAIL_FROM="perf-API@bt.com"
MAIL_TO="xyz@abc.com"
MAIL_CC=""

(echo "From: ${MAIL_FROM}"
 echo "To: ${MAIL_TO}"
 echo "Cc: ${MAIL_CC}"
 echo "subject: API Env ABC HOURLY MONITORING NODE 1 : $DATE ${report_hr}00 HOURS"
 echo "MIME-Version: 1.0"
 echo "Content-Type: text/html"
 echo "Content-Disposition: inline"
 cat "$REPORT_HTML")|/usr/sbin/sendmail -oi -t perf-API@bt.com
fi
