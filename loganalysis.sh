#!/bin/bash
loganalyze(){
    if [ $# -eq 0 ] ; then
        search=$(pwd)
    elif [ $# -eq 1 ] ; then
        if [ -d $1 ] ; then
            search=$1
        else
            echo -e "usage: arg needs to be a directory.\n"
            exit 1
        fi
    else
        echo -e "more than 1 arg is not allowed.\n"
        exit 2
    fi
    max=0
    sum=0
    for f in $(find $search -maxdepth 1 -name "*.log" -mtime -7)
    do 
        result=$(grep -c "ERROR" $f)
        echo "************************"
        echo "************************" >> ~/analysisData.log
        echo "Filename: $f <No. of errors found = $result>"
        echo "Filename: $f <No. of errors found = $result>" >> ~/analysisData.log
        sum=$((sum + result))
        if [ $max -lt $result ] ; then
            max=$result
            name_of_max=$f
        fi
    done
    echo "Total errors found:$sum"
    echo "Total errors found:$sum" > ~/summary.log
    echo "File with the max errors:$name_of_max, <error count: $max>"
    echo "File with the max errors:$name_of_max, <error count: $max>" >> ~/summary.log
}


