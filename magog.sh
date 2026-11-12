#!/usr/bin/env sh

### /// magog.sh // ConzZah // 2026-11-12 14:02 ///

# shellcheck disable=SC2009 # REASON: pgrep is not POSIX

## depcheck
deps="sqlite3 curl grep sed cut fzf tr wc"
missing_deps=""
for dep in $deps; do
! command -v "$dep" >/dev/null && missing_deps="$dep $missing_deps"
done

## if $missing_deps is empty, tell the user which are missing & exit.
[ -n "$missing_deps" ] && printf '\n%s\n\n' "--> MISSING DEPS: $missing_deps" && exit 1

## set essential vars
magog_base="$HOME/.magog"
magog_accounts_dir="${magog_base}/accounts"
magog_accounts_txt="${magog_accounts_dir}/accounts.txt"
game_id_list="${magog_base}/.tmp/game_id_list.txt"
game_id_json="${magog_base}/.tmp/game_id.json"

## standard language, platform-code and platform for games
## NOTE: $platc="1" Windows, $platc="2" Mac, $platc=3 Linux
lang="en"; platc="1"; platform="Windows"


init () {
clear_screen
## make sure '${magog_base}' exists
mkdir -p "${magog_base}"
mkdir -p "${magog_base}/.tmp"

## check if we have an active internet connection and proceed to login_to_gog
check_for_internet_connection
login_to_gog

## make sure "$index" exists and is up to date
## but only if $view_all_games is still unset
[ -z "$view_all_games" ] && gog_library_indexer

## launch fzf, so the user can choose one from their library
choose_game_via_fzf

## get the cdn links and display them
get_gog_links; display_cdn_links
}


check_if_game_exists_in_index () {
## check index.txt for $game, and evac if it's not found
## (this will also get us the full index.txt line, we'll need it for $game_id later)
! game="$(eval "grep -H -i \"$game\" $index")" && \
printf '\n%s\n\n' "--> ERROR: GAME: '$query' IS NOT IN INDEX" && exit 1
## if $pick_first_game is nonzero, print only the first line in $game.
[ -n "$pick_first_game" ] && game="$(printf '%s\n' "$game"| sed -n '1 p')"

## if $choose_game_via_args is set, assign $game to $chosen_game
[ -n "$choose_game_via_args" ] && chosen_game="$game"
return 0
}


choose_game_via_fzf () {
## lets the user choose a game with fzf
## default $fzf_header
fzf_header="--> WELCOME BACK ${user}! 
--> CHOOSE ONE OF YOUR $game_count GAMES"

sort_games () {
## sort the game(s) so there are no duplicates
chosen_game="$(printf '%s\n' "$game"| cut -d '~' -f 2| sort| uniq)"
return
}

ask_for_game () {
## ask user for a game and lock in
chosen_game="$(printf '%s\n' "$chosen_game"| fzf --header "$fzf_header")"
return
}

## if $game is empty, load $index into $game
[ -z "$game" ] && game="$(eval "cat $index")"

## NOTE: this is 'choose_game_via_args' support
## if $choose_game_via_args, AND  $pick_first_game are still unset, 
## sort out duplicates, count the lines of $chosen_game and modify $fzf_header
[ -n "$choose_game_via_args" ] && [ -z "$pick_first_game" ] && {
sort_games

## count the results
many="$(printf '%s\n' "$chosen_game"| wc -l)"

## set $fzf_header
fzf_header="--> YOU SEARCHED FOR: '$query' AND MAGOG FOUND $many RESULTS"

## ask user for a game and lock in
ask_for_game && chosen_game="$(printf '%s\n' "$game"| grep -m1 "$chosen_game")"
return
}

## if $view_all_games is nonzero, modify $fzf_header
[ -n "$view_all_games" ] && fzf_header="--> WELCOME BACK!"
sort_games

## if $total_acc_ln (total number of lines in accounts.txt) is greater than 1, 
## add the option to go back to account selection.
[ "$total_acc_ln" -gt "1" ] && chosen_game="$(printf '%s\n%s\n' "$chosen_game" '<-- SELECT ACCOUNT')"

## add the option to exit magog
chosen_game="$(printf '%s\n%s\n' "$chosen_game" 'EXIT MAGOG')"

## ask user for a game
ask_for_game

case "$chosen_game" in
'EXIT MAGOG') printf '\n%s\n\n' "--> HAVE A NICE DAY :D" && exit 0 ;;
'<-- SELECT ACCOUNT')
uid=""; user=""; index=""; acc_ln=""; query=""; game=""; chosen_game=""; view_all_games=""
login_to_gog; choose_game_via_fzf;;
esac

pick_first_game="1"
check_if_user_chose_a_game
check_if_game_exists_in_index

## if $view_all_games is nonzero, get values and re-index
[ -n "$view_all_games" ] && { 
choose_game_from_all_indexes
choose_gog_account_via_args "$uid"
gog_library_indexer
}
}


check_if_user_chose_a_game () {
## checks if the user chose a game
## if $chosen_game is empty, then no game was chosen
[ -z "$chosen_game" ] && printf '\n%s\n\n' "--> NO GAME CHOSEN." && exit 1
## if $chosen_game is NOT empty, assign it to $game
[ -n "$chosen_game" ] && game="$chosen_game"
}


get_game_id_json () {
## get game_id.json
curl -sb "$cookie" -c \
"${magog_base}/.new_gog-cookie.txt" "https://www.gog.com/en/account/gameDetails/${game_id}.json" --compressed| sed 's#\\##g'| tr ',' '\n' > "$game_id_json"
refresh_gog_cookie
}


get_gog_links () {
## get the $game_id and the human-readable game name
game_id="$(printf '%s\n' "$game"| cut -d '~' -f 1| cut -d ':' -f 2)"
gname_hr="$(printf '%s\n' "$game"| cut -d '~' -f 2)"

## get the $game_link (so we can tell dlc from basegame)
game_link="$(printf '%s\n' "$game"| cut -d '~' -f 3)"

## get game details
get_game_id_json

## if $game_id_json contains the phrase 'openlogin',
## then your gog cookie is no longer valid.
## magog  will tell the user, remove the account, and exit.
grep -q 'openlogin' "$game_id_json" && {
printf '\n%s\n\n' "--> COOKIE IS NO LONGER VALID, PLEASE SIGN IN AGAIN."
remove_gog_account
}

## get part numbers of basegame, dlc & patches, (including their version number), while omitting the easy-installers
part_list_complete=""; gparts_basegame=""; gparts_dlc=""; gparts_patches=""
part_list_complete="$(grep -o '/downloads/.*' "$game_id_json"| sed -e 's#"##g' -e 's#/downloads/##g' -e's#,$##g' -e '$d')"
gparts_basegame="$(printf '%s\n' "$part_list_complete"| grep "${game_link}/${lang}${platc}installer.*")"
gparts_dlc="$(printf '%s\n' "$part_list_complete"| grep -v "${game_link}/${lang}${platc}installer.*"| grep -o ".*${lang}${platc}installer.*")"
gparts_patches="$(printf '%s\n' "$part_list_complete"| grep -o ".*${lang}${platc}patch.*")"

## if $gparts_basegame is empty, then the game is not available for the selected platform
[ -z "$gparts_basegame" ] && printf '\n%s\n\n' "--> ERROR: $gname_hr IS NOT AVAILABLE FOR: $platform" && exit 1

## tell the user to not be impatient
printf '\n%s\n\n' "--> GENERATING CDN-LINKS FOR: '$gname_hr' PLEASE WAIT.."

## get current game version
version_basegame="$(grep -m1 '"version":' "$game_id_json"| cut -d '"' -f 4)"

## write game name & game version to cdn_links.txt
[ -f "${magog_base}/cdn_links.txt" ] && rm -f "${magog_base}/cdn_links.txt"
printf '%s\n\n' "// GAME: $gname_hr // VERSION: $version_basegame // PLATFORM: $platform //"| tee -a "${magog_base}/cdn_links.txt"

#### get the cdn links for the individual parts ####

### basegame ###
printf '\n%s\n%s\n%s\n\n' "============" " BASE GAME:" "============"| tee -a "${magog_base}/cdn_links.txt"
for part in $gparts_basegame; do
get_part_name
get_part_size
get_part_link
done

### dlc ###
[ -n "$gparts_dlc" ] && {
printf '\n\n%s\n%s\n%s\n\n' "======" " DLC:" "======"| tee -a "${magog_base}/cdn_links.txt"
for part in $gparts_dlc; do
get_part_name
get_part_size
get_part_link
done
}

### patches ###
[ -n "$gparts_patches" ] && {
printf '\n\n%s\n%s\n%s\n\n' "==========" " PATCHES:" "=========="| tee -a "${magog_base}/cdn_links.txt"
for part in $gparts_patches; do
get_part_name
get_part_size
get_part_link
done
}
}


get_part_name () {
## gets name for the $part in question
part_name="$(grep -A1 "$part" "$game_id_json"| grep -o -m1 '"name":.*'| cut -d '"' -f 4)"

## if $part_name is 'DLC', we got a placeholder,
## and need to go for title instead of name to get the actual value.
[ "$part_name" = "DLC" ] && \
part_name="$(grep -B8 "$part" "$game_id_json"| grep -o -m1 '"title":.*'| cut -d '"' -f 4)"
}


get_part_size () {
## gets filesize of the part in question
part_size="$(grep -A4 "$part" "$game_id_json"| grep -o -m1 '"size":.*'| cut -d '"' -f 4)"
}


get_part_link () {
## fetch cdn-link for the $part in question
## NOTE: with every iteration, new cookies will be set, so we never need to worry about expiry,
## UNLESS the user doesn't request a game within 9 months or terminates the session (via web in this case)
sleep 0.4
part_link="$(curl -sLIb "$cookie" -c "${magog_base}/.new_gog-cookie.txt" "https://www.gog.com/downloads/${part}"| \
grep 'location'| grep -o 'https.*')"
refresh_gog_cookie

## write $part_name, $part_size and $part_link to '${magog_base}/cdn_links'
printf '%s\n%s\n\n' "== $part_name // $part_size ==" "$part_link"| tee -a "${magog_base}/cdn_links.txt"
}


display_cdn_links () {
remove_unicode_codepoints "${magog_base}/cdn_links.txt"
clear_screen
printf '%s\n' "LINKS ARE VALID FOR 24H!" >> "${magog_base}/cdn_links.txt"
## display the result
cat "${magog_base}/cdn_links.txt"
exit 0
}


count_index_txt_lines () {
## count lines of '$index'
game_count_lines="$(wc -l "$index"| cut -d ' ' -f 1)"
}


get_game_id_list () {
## init vars
game_count=""; game_count_lines=""; current_game_count="1"
get_gamecount

## obtain all title id's and convert it into a newline seperated list
curl -sb "$cookie" -c "${magog_base}/.new_gog-cookie.txt" 'https://menu.gog.com/v1/account/licences' --compressed| \
tr '[]",' ' '| tr -s ' '| tr ' ' '\n'| sed '/^$/ d' > "$game_id_list"
refresh_gog_cookie

## if $game_id_list contains: '{"message":"Unable to authenticate."}', abort.
grep -q '{"message":"Unable to authenticate."}' "$game_id_list" && remove_gog_account

## make sure that '"$index"' exists
[ ! -f "$index" ] && touch "$index"
count_index_txt_lines
}


gog_library_indexer () {
synced="--> GAMES FOR $user HAVE BEEN SYNCED."
get_game_id_list

## check if there is any .bak file we can restore, to avoid indexing from scratch.
## (see remove_gog_account for more info on .bak files).
[ -f "$index.bak" ] && \
mv "$index.bak" "$index" 
clear_screen; printf '%s\n' "--> SYNCING ${user}'s LIBRARY, PLEASE WAIT.."; sleep 0.7; clear_screen

## if $game_count_lines and $game_count are equal, there is no need to sync. otherwise continue.
[ "$game_count" = "$game_count_lines" ] && clear_screen && printf '%s\n' "$synced" && sleep 0.7 && clear_screen && return 0

## main loop to process them gamez
while read -r game_id; do

## check if $game_id is already in index.txt,
## if it isn't, proceed to add it.
! grep -q "$game_id" "$index" && {

## show the user which game we're processing
printf '%s\n' "--> SYNCING GAMES FOR: $user [${current_game_count} // ${game_count}]"

## get game details
get_game_id_json

## get game title
game_title="$(grep -m1 'title' "$game_id_json"| cut -d '"' -f 4| sed 's#,##g'| tr -s ' ')"

## get game link
game_link="$(grep -m1 -o "/downloads/.*" "$game_id_json"| cut -d '/' -f 3)"

## GENERATE INDEX ENTRY ( DELIM: '~' )
## INDEX MAP: 1 = $game_id ~ 2 = $game_title ~ 3 = $game_link
entry="${game_id}~${game_title}~${game_link}"

## only write $entry  to index if it isn't missing $game_title and $game_link.
## this can happen in some cases (for example with game_id: 1801418160).
## those types of entries will be silently skipped, since not even gogdb has any information on them.
printf '%s\n' "$entry"| grep -q '.*~~' && clear_screen && continue

## write $entry to '"$index"'
printf '%s\n' "$entry" >> "$index"

## init vars before next iteration just to be safe
game=""; game_title=""; game_link=""; entry=""
sleep 0.4
clear_screen
}

## if $current_game_count is equal to $game_count, break out of the loop.
## (this means we have all of the games processed / reached the end)
[ "$current_game_count" = "$game_count" ] && break

## increase $current_game_count by 1 before each new iteration
current_game_count="$((current_game_count + 1))"
done < "$game_id_list"

## remove any games from index.txt that the user might have refunded
remove_refunded_games
remove_unicode_codepoints "$index"
printf '\n%s\n\n' "$synced"; sleep 0.7; clear_screen
}


remove_refunded_games () {
## check if we have any $game_id in "$index" that isn't in $game_id_list anymore.
## (when the user refunds a game, it can no longer be found on $game_id_list, and needs to be removed).
## if $game_count_lines is greater than $game_count, figure out what's no longer in $game_id_list.
count_index_txt_lines
[ "$game_count_lines" -gt "$game_count" ] && {
cp "$index" "${magog_base}/.tmp/index-${uid}.txt"
while read -r game_id; do
game_id="$(printf '%s\n' "$game_id"| cut -d '~' -f 1)"
! grep -q "$game_id" "$game_id_list" && {
refunded_game_line="$(grep -n -m1 "$game_id" "$index"| cut -d ':' -f 1)"
sed -i "$refunded_game_line d" "$index"
}
done < "${magog_base}/.tmp/index-${uid}.txt"
rm -f "${magog_base}/.tmp/index-${uid}.txt"
}
}


remove_unicode_codepoints () {
## remove (the most common) unicode codepoints
sed -i -e 's#u0026##g' -e 's#u0027##g' -e 's#u2013##g' -e 's#u2014##g' -e 's#u2019##g' -e 's#u2122##g' -e 's#u00ae##g' -e 's#u003C##g' -e 's#u003E##g' -e 's#u014d##g' "$1"
## also make sure that there are no extra spaces
tr -s ' ' < "$1" > "${magog_base}/.tmp/NoExtraSpacesPls"
mv -f "${magog_base}/.tmp/NoExtraSpacesPls" "$1"
}


clear_screen () {
## if magog was launched with set -x, 
## don't clear the screen, so debugging is still possible
! printf '%s\n' "$-"| grep -q "x" && clear
return 0
}

check_for_internet_connection () { 
printf '%s\n\n' "--> CHECKING FOR INTERNET CONNECTION.." 
! ping -c 1 'gog.com' >/dev/null 2>&1 && clear_screen && \
printf '\n%s\n\n' "--> CONNECT TO THE INTERNET AND TRY AGAIN." && exit 1
clear_screen
}

###### AUTH STUFF (cookies, account management, etc) ######

refresh_gog_cookie () {
## make sure that '.new_gog-cookie.txt' becomes our current cookie
## NOTE: '.new_gog-cookie.txt' will be created by: get_game_id_json & get_part_link
[ -f "${magog_base}/.new_gog-cookie.txt" ] && {
[ -f "$cookie" ] && cat "${magog_base}/.new_gog-cookie.txt" > "$cookie"
rm -f "${magog_base}/.new_gog-cookie.txt"
}
}


get_total_account_txt_lines () {
## create ${magog_accounts_dir}
mkdir -p "${magog_accounts_dir}"
touch "${magog_accounts_txt}"

## NOTE: $total_acc_ln are the total lines of ${magog_accounts_txt} as integer
total_acc_ln="$(wc -l < "${magog_accounts_txt}")"
}


login_to_gog () {
## get the total number of lines of '${magog_accounts_txt}'
get_total_account_txt_lines

## check if the user wanted to add a cookie manually
[ -n "$manual_gog_cookie" ] && get_gog_cookie

## check if the user wanted to login with a 2nd account (via firefox)
[ -n "$login_with_2nd_account" ] && get_gog_cookie

## if $total_acc_ln is 0, then we don't have any accounts in 'accounts.txt'
[ "$total_acc_ln" = "0" ] && get_gog_cookie

## if $total_acc_ln is equal to 1, AND $login_with_2nd_account is zero,
## get data from accounts.txt without prompting the user for an account 
## (since a selection screen makes no sense if we only have one option).
[ "$total_acc_ln" = "1" ] && [ -z "$login_with_2nd_account" ] && \
acc_ln="1" && get_data_from_accounts_txt

## if $total_acc_ln is greater than 1, and $acc_ln is still unset,
## let the user choose a account via fzf
[ "$total_acc_ln" -gt "1" ] && [ -z "$acc_ln" ]  && \
choose_gog_account_interactively
}


choose_gog_account_interactively () {
## this function is for choosing a gog account interactively
## NOTE: '$acc_ln' gets the line number of the requested account, 
## so get_data_from_accounts_txt can get the right values.
acc_ln=""
accounts="$(cut -d '~' -f 2 < "${magog_accounts_txt}")"

## give the user the option to exit magog
accounts="$(printf '%s\n%s\n' "$accounts" "EXIT MAGOG")"

## if $total_acc_ln is greater than 1, allow the user to view all games at once
[ "$total_acc_ln" -gt "1" ] && accounts="$(printf '%s\n%s\n' "VIEW ALL GAMES" "$accounts")"

## let the user choose an account, view all games at once, or exit magog
acc_ln="$(printf '%s\n' "$accounts"| fzf --header="--> CHOOSE ACCOUNT")"

## if $acc_ln is still empty, the user didn't chose any account.
[ -z "$acc_ln" ] && printf '\n%s\n\n' "--> NO ACCOUNT CHOSEN." && exit 1

case $acc_ln in
'VIEW ALL GAMES') acc_ln=""; unify_index; view_all_games="1";;
'EXIT MAGOG') printf '\n%s\n\n' "--> HAVE A NICE DAY :D" && exit 0 ;;
esac

## if the user did not select 'view all games',
## proceed to get_data_from_accounts.txt
[ -z "$view_all_games" ] && {
acc_ln="$(grep -n -m1 "$acc_ln" "${magog_accounts_txt}"| cut -d ':' -f 1)"
get_data_from_accounts_txt
}
}


choose_gog_account_via_args () {
## this function is for choosing a gog account via arguments
acc_ln=""; acc_ln="$(grep -n -m1 "$1" "${magog_accounts_txt}"| cut -d ':' -f 1)"
[ -z "$acc_ln" ] && printf '\n%s\n' "--> ERROR: GOG ACCOUNT '$1' WASN'T FOUND IN: '${magog_accounts_txt}'" && exit 1
get_data_from_accounts_txt
}


get_data_from_accounts_txt ()  {
## this function gets $uid and $user from accounts.txt at the specified line number,
## and sets $cookie & "$index" to its right values
get_data_from_accounts_txt="1"
uid="$(cut -d '~' -f 1 "${magog_accounts_txt}"| sed -n "$acc_ln p")"
user="$(cut -d '~' -f 2 "${magog_accounts_txt}"| sed -n "$acc_ln p")"
cookie="${magog_accounts_dir}/.gog-cookie-${uid}.txt"
index="${magog_accounts_dir}/index-${uid}.txt"
}


get_gog_cookie () {
## NOTE: get_gog_cookie is responsible to get the gog cookie initially, it will only be called during login.

check_if_gog_al_is_present () {
## NOTE: check_if_gog_al_is_present is strictly a sub-function of get_gog_cookie.
## if 'gog-al' doesn't appear within '.cookie-tmp' then we're not logged in and need to abort.
! grep -q 'gog-al' "${magog_accounts_dir}/.cookie-tmp" && printf '\n%s\n\n' "--> COULDN'T GET GOG COOKIE, TRY AGAIN." && \
{ rm -f "${magog_accounts_dir}/.cookie-tmp"; exit 1 ;}
}


## TODO
## if $manual_gog_cookie is set,
## check if the user provided a valid gog-al cookie
## NOTE: THE GOG-AL COOKIE ALWAYS HAS A LENGTH OF 150 CHARS (without 'gog-al=' in front)
[ -n "$manual_gog_cookie" ] && {

## if the user only provided the cookie, without prefixing it with 'gog-al=', add it
! printf '%s\n' "$manual_gog_cookie" |grep -q "^gog-al=" || \
[ "$(printf '%s' "$manual_gog_cookie"| wc -c)" = "150" ] && \
manual_gog_cookie="$(printf '%s\n' "$manual_gog_cookie"| sed 's#^#gog-al=#')"

## check if the cookie is valid
rm -f "${magog_accounts_dir}/.cookie-tmp"
curl -sc "${magog_accounts_dir}/.cookie-tmp" -H "Cookie: $manual_gog_cookie" "https://www.gog.com/userData.json" >/dev/null 2>&1

check_if_gog_al_is_present
add_gog_account
exit
}

## get gog cookie via firefox
## if ce.sh isn't available, get it
[ ! -f "${magog_base}/ce.sh" ] && curl -sLo "${magog_base}/ce.sh" "https://github.com/ConzZah/ce/raw/refs/heads/main/ce.sh"
[ -f "${magog_base}/ce.sh" ] && {

## if $total_acc_ln is 0, get the gog cookie from the last used firefox profile
[ "$total_acc_ln" = "0" ]  && {
sh "${magog_base}/ce.sh" | grep 'gog-al' > "${magog_accounts_dir}/.cookie-tmp"
check_if_gog_al_is_present
add_gog_account
exit
}

## if the user explicitly specified to login with a 2nd account, (aka --login)
## get the gog cookie via fpp (https://github.com/conzzah/fpp)
[ -n "$login_with_2nd_account" ] && {

## if firefox.sh is missing, get it.
[ ! -f "${magog_base}/firefox.sh" ] && \
curl -sLo "${magog_base}/firefox.sh" "https://github.com/ConzZah/fpp/raw/refs/heads/main/firefox.sh"

## tell the user to login and close firefox after they're done
printf '\n%s\n' "--> LOGIN TO YOUR GOG ACCOUNT AND CLOSE FIREFOX TO PROCEED.."
sleep 1 

## open firefox pointing to gog.com/#openlogin
sh "${magog_base}/firefox.sh" "https://www.gog.com/#openlogin" >/dev/null 2>&1 || \
printf '\n%s\n\n' "--> FIREFOX IS NOT INSTALLED" && exit 1

## only continue once firefox's pid is not found anymore
## (aka firefox is closed, and cookies.sqlite is unlocked)
firefox_pid="$(cat "${magog_base}/fpp/.pid")"; sleep 1
until [ -z "$firefox_pid" ]; do
firefox_pid="$(ps -ax| grep -m1 'firefox.*--allow-downgrade --profile.*fpp'| grep -v 'grep'| tr -s ' '| cut -d ' ' -f 2)"; sleep 0.5
done

## get the gog cookie and delete the fpp directory
sleep 2; sh "${magog_base}/ce.sh" "${magog_base}/fpp/cookies.sqlite"| grep 'gog-al' > "${magog_accounts_dir}/.cookie-tmp"
rm -rf "${magog_base}/fpp"
check_if_gog_al_is_present
add_gog_account
exit
}
}
}


add_gog_account () {
add_gog_account="1"
### NOTE: THIS FUNCTION WILL ONLY BE CALLED IF WE'RE ADDING A NEW ACCOUNT
## get user-id, username, and number of games
udat="$(curl -sb "${magog_accounts_dir}/.cookie-tmp" https://www.gog.com/userData.json| tr ',' '\n'| grep -oE -m3 '"userId":.*|"username":.*|{"games":.*')"

## if we're still here, and $udat is still empty after the ping succeeded, 
## then we know that we're not logged in (anymore)
[ -z "$udat" ] && printf '\n%s\n\n' "--> YOUR GOG COOKIE IS INVALID." && { 
rm -f "${magog_accounts_dir}/.cookie-tmp"
exit 1
}

## ($uid = user-id)
uid="$(printf '%s\n' "$udat"| sed -n '1 p'| cut -d '"' -f 4)"

## ($user = username)
user="$(printf '%s\n' "$udat"| sed -n '2 p'| cut -d '"' -f 4)"

## set vars & update cookie regardless of if it already exists or not
cookie="${magog_accounts_dir}/.gog-cookie-${uid}.txt"
index="${magog_accounts_dir}/index-${uid}.txt"
mv "${magog_accounts_dir}/.cookie-tmp" "$cookie"

## write $uid and $user to ${magog_accounts_txt}, only if it shouldn't already exist.
grep -q "${uid}~${user}" "${magog_accounts_txt}" && \
printf '\n%s\n\n' "--> GOG ACCOUNT '$user' EXISTS ALREADY." && exit 0
printf '%s\n' "${uid}~${user}" >> "${magog_accounts_txt}"
printf '\n%s\n\n' "--> GOG ACCOUNT '$user' SUCCESSFULLY ADDED."
gog_library_indexer
return 0
}


get_gamecount () {
[ -n "$add_gog_account" ] && game_count="$(printf '%s\n' "$udat"| sed -n '3 p'| cut -d ':' -f 2)"
[ -n "$get_data_from_accounts_txt" ] && \
game_count="$(curl -sb "$cookie" "https://menu.gog.com/v1/account/stats"| tr ',' '\n'|grep -o '{"games":.*'| cut -d ':' -f 2)"
add_gog_account=""; get_data_from_accounts_txt=""

## if $game_count is 0 or unset, then you either don't have any games on said account, or magog can't determine how many
## magog  will tell the user, remove the gog account, and exit.
[ "$game_count" = "0" ] || [ -z "$game_count" ] && {
printf '\n%s\n\n' "--> ERROR: CAN'T GET NUMBER OF GAMES FOR: $user"
remove_gog_account
}
}


remove_gog_account () {
## remove the corresponding cookie,
## but move the index to a .bak file, 
## since the user might re-login later.
## (no one wants to re-index all of their games from scratch).
[ -n "$uid" ] && {
## remove $cookie if it exists
[ -f "$cookie" ] && rm -f "$cookie"
## move index to .bak file
mv "$index" "$index.bak"
}
## delete the corresponding line from accounts.txt
[ -n "$acc_ln" ] && sed -i "$acc_ln d" "${magog_accounts_txt}"
exit
}


re_index_all_gog_accounts () {
## re-indexes all games on all present gog accounts
all_account_ids="$(cut -d '~' -f 1 < "${magog_accounts_txt}"| tr '\n' ' '| sed 's# $##')"
for account_id in $all_account_ids; do
choose_gog_account_via_args "$account_id"
gog_library_indexer
done
return 0
}


unify_index () {
## puts all index.txt files into "$index", so one can browse them all at once
index="$(find "$magog_accounts_dir/" -type f| grep 'index-.*.txt'| grep -v '.bak'| tr '\n' ' ')"
}


choose_game_from_all_indexes () {
## NOTE: ARCHITECTURE: $index:$game~$uid
## this function applies to 'choose_game_via_args' and to 'choose_game_via_fzf'
## extract $index, $game & $uid from $chosen_game
chosen_game="$game"
index="$(printf '%s\n' "$chosen_game"| cut -d ':' -f 1)"
game="$(printf '%s\n' "$chosen_game"| cut -d ':' -f 2-)"
uid="$(printf '%s\n' "$index"| grep -o 'index.*'| sed -e 's#index-##' -e 's#.txt##')"
}


choose_game_via_args () {
cookie=""; index=""
check_for_internet_connection
get_total_account_txt_lines
unify_index

## if $game is actually a gog-link, make sure only the game name remains
printf '%s\n' "$game"| grep -q 'https://www.gog.com/.*/game/.*' && \
game="$(printf '%s\n' "$game"| cut -d '/' -f 6)"

## check if $game can be found in index.txt, else evac.
check_if_game_exists_in_index

## if we have more than one line in $game,
## launch fzf so the user can choose one of them.
## NOTE: it means there are multiple possible matches.
[ "$(printf '%s\n' "$game"| wc -l)"  -gt "1" ] && {
choose_game_via_fzf
}

check_if_user_chose_a_game
choose_game_from_all_indexes
choose_gog_account_via_args "$uid"
gog_library_indexer

## get the cdn links and display them
get_gog_links; display_cdn_links
}


### PRE-LAUNCH ###
## init important variables before processing arguments
acc_ln=""; total_acc_ln=""; game=""; game_count=""; game_count_lines=""

## process arguments
while [ "$#" -gt "0" ]; do
case $1 in

## if --login was specified, set the corresponding variable and get the cookie via firefox
'--login') login_with_2nd_account="1"; shift ;;

## if -c was specified, get the gog cookie manually, instead of using firefox
'-c') shift; [ -z "$1" ] && printf '\n%s\n\n' "--> ERROR: '-c' REQUIRES A GOG-AL COOKIE AS ARGUMENT." && exit 1 
[ -n "$1" ] && manual_gog_cookie="$1"
;;

## if --user was specified, check if the account exists in accounts.txt and choose it via arguments
'-u'|'--user') shift; [ -z "$1" ] && printf '\n%s\n\n' "--> ERROR: '--user' REQUIRES AN ARGUMENT." && exit 1
choose_gog_account_via_args "$1"; shift
;;

## if -i was specified, force a (re)index of the users gog-library
'-i'|'-index'|'-INDEX') shift; check_for_internet_connection

## if $1 is empty, the user didn't specify which account to sync,
## in this case, magog will sync all available accounts
[ -z "$1" ] && re_index_all_gog_accounts && exit 0

## if $1 is NOT empty, sync the specified account (if it exists).
[ -n "$1" ] && { choose_gog_account_via_args "$1"; gog_library_indexer; exit ;}
;;

## specify platform (windows, mac, or linux)
'-w'|'-W'|'-windows'|'-WINDOWS') platc="1"; platform="Windows"; shift ;;
'-m'|'-M'|'-mac'|'-MAC') platc="2"; platform="Mac"; shift ;;
'-l'|'-L'|'-linux'|'-LINUX') platc="3"; platform="Linux"; shift ;;

## get the 1st game on the list, and don't prompt if there are more than one
'-1'|'1') pick_first_game="1"; shift ;;

## choose a game via arguments
## NOTE: $game is only ever set once per run.
'-g'|'--game') shift
[ -z "$game" ] && {
[ -z "$1" ] && printf '\n%s\n\n' "--> ERROR: '--game' REQUIRES AN ARGUMENT." && exit 1
game="$1"; query="$1"; choose_game_via_args="1"; choose_game_via_args ;}
;;

## magog help page
'-h'|'--help')
printf '%s\n' \
'
  __  ___  ___  _____ _____ _____ 
 |  \/  | / _ \|  __ \  _  |  __ \
 | .  . |/ /_\ \ |  \/ | | | |  \/
 | |\/| ||  _  | | __| | | | | __ 
 | |  | || | | | |_\ \ \_/ / |_\ \
 \_|  |_/\_| |_/\____/\___/ \____/
  by ConzZah © 2026 // MIT-LICENSE

 [OPTIONS]

 --login       login to a gog account
 -g / --game   choose a game via args
 -u / --user   choose an account via args
 -i / --index  force re-index of your gog library
 -w / -m / -l  choose between windows / mac / linux versions 
 -1            always take the first match without prompting
 -c            provide gog-al cookie manually
 -h / --help   show this help page
'
exit 0
;;

## if there is any unrecognized arg, shift it away
*) shift ;;
esac
done

### LAUNCH ###
init
