#!/bin/bash

#memory space
dataArray=()

#temporary memory to store
membin_decimal2binary=""
memory_offset=0

#convert decimal number to binary, if 2 -> reg, 8 -> mem
convert_decimal2binary_mem() {
    membin_decimal2binary=""
    temp=$1
    for weight in 128 64 32 16 8 4 2 1
    do
        if (( $temp >= $weight )); then
            bit=1
            temp=$(( $temp - $weight ))
        else
            bit=0
        fi 
            membin_decimal2binary="$membin_decimal2binary$bit"
    done
}
convert_decimal2binary_reg() {
    membin_decimal2binary=""
    temp=$1
    for weight in 2 1
    do
        if (( $temp >= $weight )); then
            bit=1
            temp=$(( $temp - $weight ))
        else
            bit=0
        fi 
            membin_decimal2binary="$membin_decimal2binary$bit"
    done
}
#convert binary number to hexadecimal number and store it on the memory
convert_binary2hex_store(){
    binary=$1
    hex=$(printf "%02X" "$((2#$binary))")
    dataArray[$2]=$hex
    memory_offset=$(( memory_offset + 1 ))
}

#check the opcode
check_line(){
    temp=""
    #if the value of reg and mem is out of range -> exit
    if (( $2 < 0 || $2 > 3 || $3 < 0 || $3 > 255 )); then
        echo -e "The value is out of range"
        exit 1
    fi 

    #load
    if grep -q "LOAD" <<< "$1"; then
        convert_decimal2binary_reg $2
        temp=$membin_decimal2binary
        temp="000001$temp"
        echo "Line $4: $1,$2,$3 ..... <VALID>"
    #store
    elif grep -q "STORE" <<< "$1"; then
        convert_decimal2binary_reg $2
        temp=$membin_decimal2binary
        temp="000010$temp"
        echo "Line $4: $1,$2,$3 ..... <VALID>"
    #addition
    elif grep -q "ADD" <<< "$1"; then
        convert_decimal2binary_reg $2
        temp=$membin_decimal2binary
        temp="000011$temp"
        echo "Line $4: $1,$2,$3 ..... <VALID>"
    #subtraction
    elif grep -q "SUB" <<< "$1"; then
        convert_decimal2binary_reg $2
        temp=$membin_decimal2binary
        temp="000100$temp"
        echo "Line $4: $1,$2,$3 ..... <VALID>"
    #quit
    elif grep -q "QUIT" <<< "$1"; then
        if (( $mem != 0 )); then
            echo "Invalid memory address"
            exit 1
        fi
        temp="00100000"
        echo "Found the <QUIT> so ending the conversion procedure ......."
    #print
    elif grep -q "PRINT" <<< "$1"; then
        if (( $mem != 0 )); then
            echo "Invalid memory address"
            exit 1
        fi
        convert_decimal2binary_reg $2
        temp=$membin_decimal2binary
        temp="001001$temp"
        echo "Line $4: $1,$2,$3 ..... <VALID>"
    #if instruction code is wrong
    else
        echo "Instruction code errors"
        exit 1
    fi
    #store opcode and memory address on the memory space
    convert_binary2hex_store $temp $memory_offset
    convert_decimal2binary_mem $3
    convert_binary2hex_store $membin_decimal2binary $memory_offset
}
#checking if the input is null or 
input_check(){
    if [ -z "$1" ]; then
        echo "The opcode part is empty"
        exit 1
    elif [ -z "$2" ]; then
        echo "The reg. part of $1,,$3 is empty"
        exit 1
    elif [ -z "$3" ]; then 
        echo "The mem. part of $1,$2, is empty"
        exit 1
    else
        return
    fi
}

#main function
if [ $# -eq 1 ] ; then
    if [[ -f $1 && $1 == *.vsc ]]; then
        asbler_file=$1
        exec 3< "$asbler_file"
        base="${asbler_file%.vsc}"
    else
        echo -e "Arg must be a .vsc file and needs to exist in the current directory"
        exit 1
    fi
elif [ $# -eq 0 ]; then
    echo -e "usage: no argument is provided"
    exit 1
else   
    echo -e "usage: more than one arguments are provided"
    exit 1
fi
# checking the argument

output_file="${base}.bin"
linenumber=1
IFS= read -r line <&3
#checking the initial static memory value...
if (( $line == 0 )) ; then
    echo "It is an QUIT program"
    linenumber=$(( linenumber + 1 ))
    IFS=',' read -r op reg mem <&3;
    if grep -q "QUIT" $op; then
        if (( $reg != 0 || $mem != 0)); then
            echo "Invalid value"
            exit 1
        fi 
        temp="00100000"
        convert_binary2hex_store $temp $memory_offset
        convert_decimal2binary_mem $mem
        convert_binary2hex_store $membin_decimal2binary $memory_offset
    fi

elif (( $line == 2 )) ; then
    echo "It is an ADD/SUB program"
    echo "-----------"
    IFS= read -r data1 <&3
    IFS= read -r data2 <&3
    if (( $data1 >= 0 && $data1 < 128 || $data2 >= 0 && $data2 < 128 )); then
        convert_decimal2binary_mem $data1
        convert_binary2hex_store $membin_decimal2binary $memory_offset
        convert_decimal2binary_mem $data2
        convert_binary2hex_store $membin_decimal2binary $memory_offset
    else
        echo -e "The initially stored data must be within the range between 0 to 127"
        exit 1
    fi
    linenumber=$(( $linenumber + 3 ))

elif [ -z "$line" ]; then
    echo "This file is empty"
    exit 1
else
    echo -e "The number of initially stored data must be either 0 or 2"
    exit 1
fi

while IFS=',' read -r op reg mem <&3; do
    input_check $op $reg $mem
    total_length=$(( ${#op} + ${#reg} + ${#mem} ))
    if (( total_length > 11 )); then
        exit 1
    fi
    check_line $op $reg $mem $linenumber
    linenumber=$(( linenumber + 1 ))
    if (( $linenumber > 103 )); then
        break
    fi
done

#printing the summary to the standard output
print_output(){
    echo ""
    echo "************"
    echo "Done with the conversion"
    echo "The content of the .bin file is:"
    for (( i=0; i<memory_offset; i++ ))
    do
        echo "${dataArray[i]}"
    done
}
#creating the output file
print_file(){
    for (( i=0; i<memory_offset; i++ ))
    do 
        echo ${dataArray[i]} >> $output_file
    done
}

print_output
print_file