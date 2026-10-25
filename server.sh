#!/bin/sh
ip=$(ifconfig eth0 | grep "inet " | awk '{print $2}' | cut -d: -f2)
listen_port=1234
pkill nc
pkill tail
apk add python3 py3-matplotlib iproute2-ss curl jq html2text
cat > /tmp/plot.py << 'EOF'
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

src, out = sys.argv[1], sys.argv[2]
years, pops = [], []
try:
    with open(src) as f:
        for line in f:
            y, p = line.strip().split(",")
            years.append(int(y))
            pops.append(int(p))
except (OSError, ValueError) as e:
    print(f"Error: cannot read {src}: {e}", file=sys.stderr)
    sys.exit(1)

if not years:
    print("Error: no data to plot", file=sys.stderr)
    sys.exit(1)

plt.plot(years, pops, marker="o")
plt.xlabel("Year")
plt.ylabel("Population")
plt.title("Estimated Resident Population")
plt.xticks(years)
plt.ticklabel_format(axis="y", style="plain")
plt.grid(True)
plt.tight_layout()
plt.savefig(out)
EOF
: > /tmp/data.log
: > /tmp/nc.log
tail -f /tmp/nc.log &
tail -n 0 -f /tmp/data.log | while true; do
	if [ -n "$busypid" ]; then
		kill "$busypid" 2> /dev/null
		pkill -f "nc -l -p $listen_port"
		busypid=
	fi

	if [ -n "$ncpid" ]; then
		exec 3>&-
		wait "$ncpid"
	fi

	rm -f /tmp/reply
	mkfifo /tmp/reply
	exec 3<> /tmp/reply
	nc -lv -p "$listen_port" < /tmp/reply >> /tmp/data.log 2>> /tmp/nc.log 3>&- &
	ncpid=$!

	if [ -z "$port" ]; then
		port=$(ss -ltn | awk 'NR == 2 {print $4}' | awk -F: '{print $NF}')
		echo "The server is running at Link addr:$ip, port=$port"
		echo "..............."
	fi

	read -r line || break
	echo "Request: $line"

	(
		while true; do
			echo "Error: server is busy with another request. Request rejected." \
				| nc -l -p "$listen_port" >> /tmp/reply 2>&1
		done
	) 3>&- &
	busypid=$!

	if [ "$line" = "assignment" ]; then

		URL="https://www.sydney.edu.au/units/INFO1112/2026-S2C-ND-CC"
		result=$(curl -sS $URL | html2text -nobs -width 300 | grep -A 2 "Assignment 2" | tr "\n" " " | tr -s " ")
		echo "$result"
		
		if [ -z "$result" ];then
			echo "Error: curl failure" > /tmp/reply; continue
		fi
		title=$(echo "$result" | grep -oE 'Assignment [0-9]+' | head -n 1)
		topic=$(echo "$result" | awk -F'-' '{print $2}' | awk -F' ' '{print $1}')
		due_date=$(echo "$result" | grep -oE '[0-9]{2} [A-Z][a-z]{2} [0-9]{4} at [0-9]{1,2}:[0-9]{2}' | sed 's/ at / /')
		points=$(echo "$result" | grep -oE '[0-9]+%' | sed 's/%//'| head -n 1)

		jq -n --arg title "$title" --arg topic "$topic" --arg due_date "$due_date" --arg points "$points" '{title: $title, topic: $topic,due_date: $due_date, points: ($points | tonumber)}' > assignment.json
		cat assignment.json > /tmp/reply
	elif [ "$line" = "population" ]; then

		URL="https://dbr.abs.gov.au/processedData/csv/STE_1.csv"
		result=$(curl -s $URL | grep "ERP_P_20" | awk -F',' '{print $NF}')
		echo "The Estimated residential population of NSW was $result"
		curl -s $URL | tr -d '\r' | awk -F',' 'NR == 1 { for (i = 4; i <= NF; i++) year[i] = $i; next } $1 == "ERP_P_20" { for (i = 4; i <= NF; i++) if ($i != "") print year[i] "," $i }' > /tmp/population.csv
		
		if [ ! -s /tmp/population.csv ]; then
			echo "Error: population data not found in CSV" > /tmp/reply; continue
		fi

		if ! python3 /tmp/plot.py /tmp/population.csv /tmp/population.png 2> /tmp/plot.err; then
			echo "Error: failed to generate plot: $(cat /tmp/plot.err)" > /tmp/reply; continue
		fi
		cat /tmp/population.png > /tmp/reply
	else 
		API="https://maps.six.nsw.gov.au/arcgis/rest/services/public/NSW_POI/MapServer/0/query"
		if [ -z "$line" ]; then
			echo "Error: usage: <name> or <lat>,<long>" > /tmp/reply; continue
		fi

		if echo "$line" | grep -qE '^-?[0-9]+(\.[0-9]+)?, *-?[0-9]+(\.[0-9]+)?$'; then
			lat=$(echo $line | cut -d',' -f1)
			lon=$(echo $line | cut -d',' -f2 | tr -d ' ')
			name="$line"
		else
			name=$(echo $line | tr '[:lower:]' '[:upper:]')
			safe=$(echo $line | sed "s/'/''/g")
			response=$(curl -s -G \
				--data-urlencode "where=poiname='$safe'" \
				--data-urlencode "outFields=poiname" \
				--data-urlencode "returnGeometry=true" \
				--data-urlencode "outSR=4326" \
				--data-urlencode "f=json" \
				"$API") || { echo "Error: could not connecy to NSQ POI service" > /tmp/reply; continue; }
			if [ "$(echo "$response" | jq -r '.features | length')" -eq 0 ];then
				echo "Error: This POI is an invalid Input" > /tmp/reply ; continue
			fi
			lat=$(echo $response | jq -r '.features[0].geometry.y')
			lon=$(echo $response | jq -r '.features[0].geometry.x')
		fi
		
		response=$(curl -s -G \
			--data-urlencode "geometry=$lon,$lat" \
			--data-urlencode "geometryType=esriGeometryPoint" \
			--data-urlencode "inSR=4326" \
			--data-urlencode "spatialRel=esriSpatialRelIntersects" \
			--data-urlencode "distance=300" \
			--data-urlencode "units=esriSRUnit_Meter" \
			--data-urlencode "outFields=*" \
			--data-urlencode "returnGeometry=true" \
			--data-urlencode "outSR=4326" \
			--data-urlencode "f=json" \
			"$API") || { echo "Error: could not connect to NSW POI service" > /tmp/reply; continue; }
		if [ $(echo "$response" | jq -r '.features | length') -eq 0 ]; then
			echo "Error: NSW POI service returned an error" > /tmp/reply
		fi
		echo $response > /tmp/reply
	fi
done
