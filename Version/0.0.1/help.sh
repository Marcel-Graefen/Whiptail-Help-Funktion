#!/bin/bash

declare -A META_NAME
declare -A META_BACKTITLE=()
declare -A META_LANGUAGE=()
declare -A META_LANGUAGE_EN=()
declare -a ALL_LANG=()
declare -a LANG_CODE="de"

declare -g SYS_MIN_WIDTH=50
declare -g SYS_MAX_WIDTH=150
declare -g SYS_MIN_HEIGHT=10
declare -g SYS_MAX_HEIGHT=80
declare -g SYS_PADDING=10

declare -a PARSING_LANG_CODE

build_breadcrumb() {

    local bc=""
    local backtitle="${META_BACKTITLE["$LANG_CODE"]:-HELP SYSTEM}"

    # If there is no history and no current menu → only Root
    if [[ ${#MENU_HISTORY[@]} -eq 0 && -z "$CURRENT_MENU" ]]; then
        bc="$backtitle"
    else
        bc="$backtitle"

        # Go through history
        for h in "${MENU_HISTORY[@]}"; do
            local name="${MENU[$LANG_CODE,$h,name]}"
            [[ -z "$name" ]] && name="$h"
            bc="$bc › ${name//_/ }"
        done

        # Current menu
        if [[ -n "$CURRENT_MENU" ]]; then
            local name="${MENU[$LANG_CODE,$CURRENT_MENU,name]}"
            [[ -z "$name" ]] && name="$CURRENT_MENU"
            bc="$bc › ${name//_/ }"
        fi
    fi

    # Fallback, if no letter is included
    [[ ! "$bc" =~ [a-zA-Z] ]] && bc="$backtitle"

    echo "$bc"
}



calculate_dimensions() {

  local content="$1"
  local TERM_WIDTH=$(tput cols)
  local TERM_HEIGHT=$(tput lines)
  local width height file_height

  if [[ -f "$content" ]]; then
    # File - already handles empty lines correctly
    local max_len=$(awk '{if(length>m)m=length}END{print m}' "$content" 2>/dev/null || echo 0)
    width=$((max_len))
    height=$(wc -l < "$content" 2>/dev/null || echo 0)
  else
    # extinput - must handle paragraphs correctly
    local line_count=0
    local max_len=0

    # Leave IFS empty to retain leading/trailing spaces
    while IFS= read -r line; do
      # Empty lines still count (for paragraphs)
      ((line_count++))
      # Only non-empty lines for width calculation
      if [[ -n "$line" ]]; then
        (( ${#line} > max_len )) && max_len=${#line}
      fi
    done < <(echo "$content")

    width=$((max_len + 5))
    height=$((line_count + 7))
    file_height="$height"
  fi

  # Limitations
  (( width < SYS_MIN_WIDTH )) && width=$SYS_MIN_WIDTH
  (( width > SYS_MAX_WIDTH )) && width=$SYS_MAX_WIDTH
  (( width > TERM_WIDTH - 10 )) && width=$((TERM_WIDTH - 10))
  (( height < SYS_MIN_HEIGHT )) && height=$SYS_MIN_HEIGHT
  (( height > SYS_MAX_HEIGHT )) && height=$SYS_MAX_HEIGHT
  (( height > TERM_HEIGHT - 5 )) && height=$((TERM_HEIGHT - 5))

  echo "$width $height ${file_height:-$height}"

}




pars_meta() {

  [[ -z "$INI_FILE" ]] && { echo "Usage: parser <file.ini>"; return 1; }

  local in_meta=0
  local -A _meta_temp

  while IFS= read -r line || [ -n "$line" ]; do
    # remove leading and trailing spaces
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" =~ ^[\#\;] ]] && continue

    # Start Meta-Block
    if [[ "$line" =~ ^\[meta\]$ ]]; then
      in_meta=1
      continue
    fi

    if [[ $in_meta -eq 1 ]]; then
      # read key=value
      if [[ "$line" =~ ^([a-zA-Z_]+)=(.*)$ ]]; then
          _meta_temp["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
      fi

      # End of meta block at the first other section header
      if [[ "$line" =~ ^\[.*\]$ && ! "$line" =~ ^\[meta\]$ ]]; then
          break
      fi
    fi
  done < "$INI_FILE"

  [[ -n "${_meta_temp[lang_code]}" ]] && PARSING_LANG_CODE="${_meta_temp[lang_code]}"

  ALL_LANG+=("$PARSING_LANG_CODE")

  # TODO Prüfungen hier auch ob name = Muss Name
  [[ -n "${_meta_temp[name]}" ]] && META_NAME["$PARSING_LANG_CODE"]="${_meta_temp[name]}"

  [[ -n "${_meta_temp[backtitle]}" ]] && META_BACKTITLE["$PARSING_LANG_CODE"]="${_meta_temp[backtitle]}"

  [[ -n "${_meta_temp[language]}" ]] && META_LANGUAGE["$PARSING_LANG_CODE"]="${_meta_temp[language]}"

  [[ -n "${_meta_temp[language_en]}" ]] && META_LANGUAGE_EN["$PARSING_LANG_CODE"]="${_meta_temp[language_en]}"

}





# --- Globale Arrays ---
declare -A TYPE
declare -A MENU
declare -A CONTENT


parse_menu_content() {

  # Temporäre Container
  local current_section=""
  local current_type=""
  local current_code=""

  declare -A _menu_name _menu_keys _menu_values
  declare -A _content_name _content_keys _content_values
  declare -A _type_map

  # === Datei lesen ===
  while IFS= read -r line || [ -n "$line" ]; do
    # Trim spaces
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip comments and empty lines
    [[ -z "$line" || "$line" =~ ^[\#\;] ]] && continue

    # Section detection
    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"

      # Extract type (menu or content) and code
      current_type="${current_section%%:*}"
      current_code="${current_section#*:}"

      # Allow only menu:* or content:*
      if [[ "$current_type" == "menu" || "$current_type" == "content" ]]; then
        _type_map["$current_code"]="$current_type"
      else
        # Ignore all other sections
        current_type=""
        current_code=""
      fi
      continue
    fi

    # If section is not menu/content → skip lines
    [[ -z "$current_type" ]] && continue

    # Key=Value line
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"

      # Menu section
      if [[ "$current_type" == "menu" ]]; then
        if [[ "$key" == "name" ]]; then
          _menu_name["$current_code"]="$value"
        else
          local existing_keys="${_menu_keys[$current_code]}"
          local existing_values="${_menu_values[$current_code]}"

          _menu_keys["$current_code"]="${existing_keys:+$existing_keys|}$key"
          _menu_values["$current_code"]="${existing_values:+$existing_values|}$value"
        fi
      fi

      # Content section
      if [[ "$current_type" == "content" ]]; then
        if [[ "$key" == "name" ]]; then
          _content_name["$current_code"]="$value"
        else
          local existing_keys="${_content_keys[$current_code]}"
          local existing_values="${_content_values[$current_code]}"

          _content_keys["$current_code"]="${existing_keys:+$existing_keys|}$key"
          _content_values["$current_code"]="${existing_values:+$existing_values|}$value"
        fi
      fi
    fi
  done < "$INI_FILE"

  # === Globale Arrays befüllen ===
  for code in "${!_type_map[@]}"; do
    TYPE["$PARSING_LANG_CODE,$code"]="${_type_map[$code]}"
  done

  for code in "${!_menu_name[@]}"; do
    MENU["$PARSING_LANG_CODE,$code,name"]="${_menu_name[$code]}"
  done
  for code in "${!_menu_keys[@]}"; do
    MENU["$PARSING_LANG_CODE,$code,key"]="${_menu_keys[$code]}"
    MENU["$PARSING_LANG_CODE,$code,value"]="${_menu_values[$code]}"
  done

  for code in "${!_content_name[@]}"; do
    CONTENT["$PARSING_LANG_CODE,$code,name"]="${_content_name[$code]}"
  done
  for code in "${!_content_keys[@]}"; do
    CONTENT["$PARSING_LANG_CODE,$code,key"]="${_content_keys[$code]}"
    CONTENT["$PARSING_LANG_CODE,$code,value"]="${_content_values[$code]}"
  done

}



set_language_menu() {

  MENU_HISTORY=()
  CURRENT_MENU="Language"
  local title="${META_LANGUAGE["$LANG_CODE"]}"

  local breadcrumb
  breadcrumb=$(build_breadcrumb)

  local _keys=()
  local _value=()
  local options=()

  for k in "${!ALL_LANG[@]}"; do
    _keys+=("${META_LANGUAGE["${ALL_LANG[$k]}"]}")
    _value+=("${META_LANGUAGE_EN["${ALL_LANG[$k]}"]}")
    options+=("${_keys[$k]}" "${_value[$k]}")
  done

  local choice
  choice=$(whiptail --backtitle "$breadcrumb" \
      --title "$title" \
      --menu "Bitte wählen:" 0 $SYS_MIN_WIDTH 0  \
      --default-item "${META_LANGUAGE["$LANG_CODE"]}" \
      --ok-button "Auswählen" \
      --cancel-button "Zurück" \
      "${options[@]}" \
      3>&1 1>&2 2>&3)

  local status=$?

  if [[ $status -eq 1 ]]; then      # back to Main Menu
    show_menu
  elif [[ $status -eq 255 ]]; then  # Close by ESC
    exit
  fi

  for k in "${!META_LANGUAGE[@]}"; do
    if [[ "${META_LANGUAGE[$k]}" == "$choice" ]]; then
      found_key="$k"
      break
    fi
  done

  LANG_CODE="$found_key"

  show_menu

}




  show_text_with_buttons() {

    local title="$1"
    local text="$2"
    local yes_button="${3:-$BTN_OK}"
    local no_button="$4"
    read -r width height file_height < <(calculate_dimensions "$text")

    if [[ -z "$no_button" ]]; then
      # Only one button - use msgbox
      whiptail --backtitle "$(build_breadcrumb)" \
               --title "$title" \
               --ok-button "$yes_button" \
               --msgbox "$text" "$height" "$width"
    else
      # Two buttons - use yesno
      whiptail --backtitle "$(build_breadcrumb)" \
               --title "$title" \
               --yes-button "$yes_button" \
               --no-button "$no_button" \
               --yesno "$text" "$height" "$width"
    fi

  }


  show_file_with_buttons() {

    local title="$1"
    local file="$2"
    local yes_button="${3:-$BTN_OK}"
    local no_button="$4"

      # TODO  Prüfung ob datei esestiert einbauen

    local file_content=$(cat "$file")
    read -r width height file_height < <(calculate_dimensions "$file_content")

    # width=$((width - 16))

    if (( file_height > $(tput lines) )); then

      if [[ -z "$no_button" ]]; then
        # Only one button - use msgbox
        whiptail --backtitle "$(build_breadcrumb)" \
                --title "$title" \
                --ok-button "$yes_button" \
                --scrolltext \
                --msgbox "$file_content" "$height" "$width"
      else
        # Two buttons - use yesno
        whiptail --backtitle "$(build_breadcrumb)" \
                --title "$title" \
                --yes-button "$yes_button" \
                --no-button "$no_button" \
                --scrolltext \
                --yesno "$file_content" "$height" "$width"
      fi

    else

      if [[ -z "$no_button" ]]; then
        # Only one button - use msgbox
        whiptail --backtitle "$(build_breadcrumb)" \
                --title "$title" \
                --ok-button "$yes_button" \
                --msgbox "$file_content" "$height" "$width"
      else
        # Two buttons - use yesno
        whiptail --backtitle "$(build_breadcrumb)" \
                --title "$title" \
                --yes-button "$yes_button" \
                --no-button "$no_button" \
                --yesno "$file_content" "$height" "$width"
      fi

    fi

  }



show_content() {
  local key="$1"
  local yes_button="Zurück"
  local no_button="Weiter"

  # Breadcrumb for Whiptail --backtitle
  local breadcrumb
  breadcrumb=$(build_breadcrumb)

  # Read title and content
  local title="${CONTENT["$key,name"]}"
  IFS='|' read -r -a keys <<< "${CONTENT["$key,key"]}"
  IFS='|' read -r -a values <<< "${CONTENT["$key,value"]}"

  local total_pages=${#values[@]}
  local current_index=0

  while (( current_index < total_pages )); do
    local page_title="$title"
    (( total_pages > 1 )) && page_title="$title (Page $((current_index + 1))/$total_pages)"

    local content="${values[$current_index]}"
    local content_type="${keys[$current_index]}"

    (( current_index == total_pages - 1 )) && no_button="Schließen"
    # Show Whiptail Dialog
    local exit_status=0
    if (( total_pages == 1 )); then
      # only one page → only OK-Button
      if [[ "$content_type" == "text" ]]; then
        show_text_with_buttons "$page_title" "$content" "$no_button"
      else
        show_file_with_buttons "$page_title" "$content" "$no_button"
      fi
      exit_status=$?

      # Close by ESC
      [[ "$exit_status" -eq 255 ]] && exit

      break  # Just one page, done
    else
      # multiple pages → Back/Next buttons
      if [[ "$content_type" == "text" ]]; then
        show_text_with_buttons "$page_title" "$content" "$yes_button" "$no_button"
      else
        show_file_with_buttons "$page_title" "$content" "$yes_button" "$no_button"
      fi
      exit_status=$?
    fi

    # Exit-Code auswerten
    case $exit_status in
      0)  # Back
        if (( current_index > 0 )); then
          ((current_index--))
        else
          break  # First Page → Cancel
        fi
        ;;
      1)  # Continue
        if (( current_index < total_pages - 1 )); then
          ((current_index++))
        else
          break  # last page → cancel
        fi
        ;;
      255) exit ;; # Close by ESC
      *) break ;;
    esac
  done

}







show_menu() {

    local CODE="${1:-menu}"  # Starting point: Root
    local next_code=""

    # Menu history for breadcrumbs
    MENU_HISTORY=()
    CURRENT_MENU=""

    while true; do
        CURRENT_MENU="$CODE"
        local breadcrumb
        breadcrumb=$(build_breadcrumb)

        # Read title
        local title="${MENU[$LANG_CODE,$CODE,name]}"
        [[ -z "$title" ]] && title="Menü $CODE"

        # Keys and values
        local keys="${MENU[$LANG_CODE,$CODE,key]}"
        local values="${MENU[$LANG_CODE,$CODE,value]}"

        # Check if menu exists
        if [[ -z "$keys" || -z "$values" ]]; then
            whiptail --title "Fehler" --backtitle "$breadcrumb" \
                --msgbox "Kein Menü für Code: $CODE" 10 50
            return
        fi

        # Build menu options
        local menu_items=()
        IFS='|' read -r -a key_arr <<< "$keys"
        IFS='|' read -r -a val_arr <<< "$values"

        # Mapping Key -> Original for Return
        declare -A display_to_key

        for i in "${!key_arr[@]}"; do
            local original_key="${key_arr[$i]}"         # Count how many numbers
            local display_key="$((10#$original_key))"   # remove leading zeros
            display_to_key["$display_key"]="$original_key"
            menu_items+=("$display_key" "${val_arr[$i]}")
        done

        # Reverse option
        local parent=""
        if [[ "$CODE" != "menu" ]]; then
            if [[ "$CODE" != *"-"* ]]; then
                parent="menu"
            else
                parent="${CODE%-*}"
            fi
        else
            menu_items+=("${LANG_CODE^^}" "Change Language")
        fi

      # Calculate menu size
        local max_len=0
        for i in "${menu_items[@]}"; do (( ${#i} > max_len )) && max_len=${#i}; done
        local TERM_WIDTH=$(tput cols)
        local width=$((max_len + SYS_PADDING*2))
        (( width < SYS_MIN_WIDTH )) && width=$SYS_MIN_WIDTH
        (( width > SYS_MAX_WIDTH )) && width=$SYS_MAX_WIDTH
        (( width > TERM_WIDTH - 10 )) && width=$((TERM_WIDTH - 10))
        local height=$(( ${#menu_items[@]} / 2 ))
        (( height < SYS_MIN_HEIGHT )) && height=$SYS_MIN_HEIGHT
        (( height > SYS_MAX_HEIGHT )) && height=$SYS_MAX_HEIGHT
        local menu_height=$height

        # Show whiptail menu
        local choice

        # It is not the main menu
        if [[ "$CODE" != "menu" ]]; then
          choice=$(whiptail --title "$title" --backtitle "$breadcrumb" \
            --menu "Bitte wählen:" \
            --ok-button "Auswählen" \
            --cancel-button "Zurück" \
            "$menu_height" "$width" 0 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3)
        else
          # if it is the main menu
          choice=$(whiptail --title "$title" --backtitle "$breadcrumb" \
            --menu "Bitte wählen:" \
            --ok-button "Auswählen" \
            --cancel-button "Schließen" \
            "$menu_height" "$width" 0 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3)
        fi

          local status=$?

          if [[ $status -eq 1 ]]; then
            # Back or Exit
            if [[ ${#MENU_HISTORY[@]} -eq 0 ]]; then
              exit 0
            fi
            CODE="$parent"
            unset 'MENU_HISTORY[-1]'
            continue
          elif [[ $status -eq 255 ]]; then # Closing by ESC
            exit 0
          fi

         [[ "$choice" == "${LANG_CODE^^}" ]] && { set_language_menu; return 0; }


        # Find original key again
        local choice_val="$choice"
        local choice_key="${display_to_key[$choice_val]}"

        # Assemble the next code
        if [[ "$CODE" == "menu" ]]; then
            next_code="$choice_key"
        else
            next_code="${CODE}-${choice_key}"
        fi

        # Check TYPE -> Is it a menu or content?
        local next_type="${TYPE[$LANG_CODE,$next_code]}"
        if [[ "$next_type" == "menu" ]]; then
            MENU_HISTORY+=("$CODE")
            CODE="$next_code"
            continue
        elif [[ "$next_type" == "content" ]]; then

          show_content $LANG_CODE,$next_code
          continue

        else
            local position=$(($choice - 1)) # Invoked key - 1 because keys start at 1 and the array starts at 0
            IFS='|' read -r -a val_arr <<< "$values"  # write values in array

            local text="Keine weiteren Inhalte für '"${val_arr[$key]}"' gefunden."

            read -r width height file_height < <(calculate_dimensions "$text")

            whiptail --backtitle "$breadcrumb" \
              --title "Not Found" \
              --msgbox "$text" \
               "$height" "$width" \
            continue
        fi
    done
}








INI_FILE="../parser.de.ini"
pars_meta
parse_menu_content


INI_FILE="../parser.en.ini"
pars_meta
parse_menu_content

LANG_CODE="de"

show_menu



# TODO
#
# - Language Management System integrieren
# - Prüfungen in der Funktion <pars_meta> <99>
#   - Ist <lang_code> & <name> in meta ?
#   - Ist <name> = <muss name> ?
# - Noch Bauen:
#   - Error/Warning Funktion (whiptail)
#   - File Validierer/Prüfer ob Exist
#   - Log Funktion ?
# - Terminal Typ Prüfen

# - Funktion Kommentieren
# - Dokumentation Schreiben
