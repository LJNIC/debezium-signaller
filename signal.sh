#!/bin/sh
set -e

create_filters() {
	set -e
	choice=$(gum choose --header "Choose a table, or 'done' to continue" $(echo "$choices" | tr '\n' ' ') "done")
	if [ "$choice" = "done" ]; then
		filters="$(echo "$filters" | sed 's/..$//')]"
		echo "$filters"
	else
		query=$(gum input --prompt "Filter> " | sed "s/'/''/g")
		filters="${filters}{\"data-collection\": \"${choice}\", \"filter\": \"${query}\"}, "
		choices=$(echo "$choices" | sed "s/${choice}//")
		create_filters
	fi
}

save_database() {
	printf "%s\n%s\n%s" "$DATABASE" "$USER" "$TABLE" > "$CONFIG"
	gum style --foreground="#5edb6a" "Saved to ~/.config/signal.conf ✓"
}

generate_summary() {
	id_template="$(gum style --bold "id:") $(gum style --foreground="247" "$ID")"
	signal_template="$(gum style --bold "signal:") $(gum style --foreground="247" "$SIGNAL")"
	template="${id_template}\n${signal_template}"

	if [ "$TABLES" ]; then
		lines=$(($(printf "%s" "$TABLES" | wc -l) + 1))
		half=$((("$lines" + 1) / 2))
		first_half=$(gum style --foreground="247" $(printf "%s" "$TABLES" | head -n "$half"))
		if [ $(("$lines" % 2)) -ne 0 ]; then
			half=$(("$half" - 1))
		fi
		second_half=$(gum style --foreground="247" "$(printf "%s" "$TABLES" | tail -n "$half")")
		table_template="$(gum style --bold "tables:")\n$(gum join --horizontal "$first_half" " $second_half")"
		type_template="$(gum style --bold "type:") $(gum style --foreground="247" "$TYPE")"
		template="${template}\n${table_template}\n${type_template}"
	fi

	header="───$(gum style --bold --foreground="99" "Signal")"
	summary=$(printf "$template" | gum style --padding="0 1 0 1" --border="rounded")
	header=$(echo "$summary" | head -n 1 | sed "s/─────────/${header}/")
	gum join --vertical "${header}" "$(printf "$summary" | tail -n +2)"
}

build_json() {
	json="{\"data-collections\": [${COLLECTIONS}]"
	if [ "$TYPE" ]; then
		json="${json}, \"type\": \"$(echo ${TYPE} | tr '[:lower:]' '[:upper:]')\" "
	fi

	if [ "$CONDITIONS" ]; then
		json="${json}, \"additional-conditions\": ${CONDITIONS}"
	fi
	json="${json}}"
	echo "$json"
}

send_signal() {
	if [ "$HAS_DATA" ]; then
		JSON=$(build_json)
		COMMAND="INSERT INTO ${TABLE} (id, type, data) values('${ID}', '${SIGNAL}', '${JSON}');"
	else
		COMMAND="INSERT INTO ${TABLE} (id, type) values('${ID}', '${SIGNAL}');"
	fi
	RESULT=$(psql -U "$USER" "$DATABASE" -c "$COMMAND")
	gum style --foreground="#5edb6a" "Signal sent ✓"
}

gum style --bold "Debezium Signaller"
SIGNAL=$(gum choose --header "What kind of signal?" \
	"execute-snapshot" \
	"stop-snapshot" \
	"pause-snapshot" \
	"resume-snapshot")

CONFIG=~/.config/signal.conf
if [ -f "$CONFIG" ]; then
	DATABASE=$(head -n 1 "$CONFIG")
	USER=$(head -n 2 "$CONFIG" | tail -n 1)
	TABLE=$(tail -n 1 "$CONFIG")
	export PGPASSWORD=$(gum input --password --prompt "Password for ${USER} (won't be saved)> ")
else
	DATABASE=$(gum input --prompt "Database> ")
	USER=$(gum input --prompt "User> ")
	export PGPASSWORD=$(gum input --prompt "Password for ${USER} (won't be saved)> ")
	TABLE=$(gum input --prompt "Table> ")
	gum confirm "Save database information?" && (save_database && sleep 0.75)
fi

if [ "$SIGNAL" = "execute-snapshot" ] || [ "$SIGNAL" = "stop-snapshot" ]; then
	HAS_DATA=true
	TYPE=$(gum choose --header "What kind of snapshot?" "incremental" "blocking")
	DATABASE_TABLES=$(psql -U "$USER" "$DATABASE" -c \
		"SELECT schemaname, tablename 
		 FROM pg_catalog.pg_tables 
		 WHERE schemaname != 'pg_catalog' AND schemaname != 'information_schema' AND tablename != '${TABLE}';")
	DATABASE_TABLES=$(echo "$DATABASE_TABLES" | head --lines=-1 | tail --lines=+3 | tr -d ' ' | tr '|' '.' | tr '\n' ' ')
	TABLES=$(gum choose --header "Tables:" --no-limit $(echo "$DATABASE_TABLES"))
	if [ "$TABLES" ]; then
		choices="$TABLES"
		filters="["
		set +e
		CONDITIONS=$(gum confirm "Add any filters?" && create_filters)
		set -e
	fi
	COLLECTIONS="\"$(echo "$TABLES" | tr '\n' ',' | sed 's/,/","/g' | xargs -0 basename -s ',"')"
fi

ID=$(gum input --prompt "ID for the signal? " --placeholder "Leave blank for random UUID")
if [ -z "$ID" ]; then
	ID=$(uuidgen)
fi

generate_summary

gum confirm "Send this signal to ${DATABASE}/${TABLE}?" \
	&& send_signal \
	|| gum style --bold --foreground="161" "Signal cancelled ✗"

