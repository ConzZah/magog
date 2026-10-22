#!/usr/bin/env sh

### /// magog.sh // ConzZah // 2026-10-22 02:50 ///

## depcheck
deps="firefox curl grep sed cut fzf tr wc"
missing_deps=""
for dep in $deps; do
! command -v "$dep" >/dev/null && missing_deps="$dep"
done

## if $missing_deps is empty, tell the user which are missing & exit.
[ -n "$missing_deps" ] && printf '\n%s\n\n' "--> MISSING DEPS: $missing_deps" && exit 1


init () {
## make sure '$HOME/.magog' exists
[ ! -d "$HOME/.magog" ] && mkdir -p "$HOME/.magog"

## make sure '$HOME/.magog/index.txt' exists,
## if it doesn't, run gog_library_indexer.
[ ! -f "$HOME/.magog/index.txt" ] && gog_library_indexer

## clean '$HOME/.magog/cdn_links.txt' before doing anything
rm -f "$HOME/.magog/cdn_links.txt" >/dev/null

## if $game is nonzero, the user provided input via arguments.
## check if the user input is a gog-link and make sure only the game name remains
[ -n "$game" ] && {
printf '%s\n' "$game"| grep -q 'https://www.gog.com/.*/game/.*' && \
game="$(printf '%s\n' "$game"| cut -d '/' -f 6)"

## check if $game can be found in index.txt, else evac.
check_if_game_exists_in_index

## if we have more than one line in $game,
## launch fzf so the user can choose one of them.
## NOTE: it means there are multiple possible matches,
##  this edge case may happen when the user provides a game name as argument and has games with similar names.
[ "$(printf '%s\n' "$game"| wc -l)"  -gt "1" ] && {
chosen_game=""
chosen_game="$(printf '%s\n' "$game"| cut -d '~' -f 2| fzf --header "--> CHOOSE A GAME")" 
check_if_user_chose_a_game_with_fzf
check_if_game_exists_in_index
}
}

## if $game is empty, the user didn't provide any input via arguments.
## launch fzf, so the user can choose one from their library
[ -z "$game" ] && {
chosen_game=""
chosen_game="$(cut -d '~' -f 2 < "$HOME/.magog/index.txt"| fzf --header "--> CHOOSE A GAME")"
check_if_user_chose_a_game_with_fzf
check_if_game_exists_in_index
}

## if we're still here, get the cdn links and display them
get_gog_links; display_cdn_links
}


check_if_user_chose_a_game_with_fzf () {
## checks if the user chose a game with fzf
## if $chosen_game is empty, then no game was chosen
[ -z "$chosen_game" ] && printf '\n%s\n\n' "--> NO GAME CHOSEN." && exit 1

## if $chosen_game is NOT empty, assign it to $game
[ -n "$chosen_game" ] && game="$chosen_game"
}


check_if_game_exists_in_index () {
## check index.txt for $game, and evac if it's not found
## (this will also get us the full index.txt line, we'll need it for $game_id later)
! game="$(grep -i "$game" "$HOME/.magog/index.txt")" && \
printf '\n%s\n\n' "--> ERROR: GAME: '$game' IS NOT IN INDEX" && exit 1
}


get_gog_links () {
## get the $game_id and the human-readable game name
game_id="$(printf '%s\n' "$game"| cut -d '~' -f 1)"
gname_hr="$(printf '%s\n' "$game"| cut -d '~' -f 2)"

## get the $game_link (so we can tell dlc from basegame)
game_link="$(printf '%s\n' "$game"| cut -d '~' -f 3)"

## get game details from ${game_id}.json
get_game_id_json () { game="$(curl -sb "$HOME/.magog/.gog-cookie.txt" "https://www.gog.com/en/account/gameDetails/${game_id}.json" --compressed| sed 's#\\##g'| tr ',' '\n')" ;}
get_game_id_json

## if $game contains the phrase 'openlogin', 
## then your gog cookie is no longer valid.
## magog will try to fetch another one, before trying again.
printf '%s\n' "$game"| grep -q 'openlogin' && {
rm -f "$HOME/.magog/.gog-cookie.txt"
get_gog_cookie && get_game_id_json || exit 1
}

## get part numbers of basegame, dlc & patches, (including their version number), while omitting the easy-installers
part_list_complete="$(printf '%s\n' "$game"| grep -o '/downloads/.*'| sed -e 's#"##g' -e 's#/downloads/##g' -e's#,$##g' -e '$d')"
gparts_basegame="$(printf '%s\n' "$part_list_complete"| grep "${game_link}/en1installer.*")"
gparts_dlc="$(printf '%s\n' "$part_list_complete"| grep -v "${game_link}/en1installer.*"| grep -o '.*en1installer.*')"
gparts_patches="$(printf '%s\n' "$part_list_complete"| grep -o '.*en1patch.*')"

## get current game version
version_basegame="$(printf '%s\n' "$game"|grep -m1 '"version":' | cut -d '"' -f 4)"

## tell the user to not be impatient
printf '\n%s\n\n' "--> GENERATING CDN-LINKS FOR: '$gname_hr' PLEASE WAIT.."

## write game name & game version to cdn_links.txt
printf '\n%s\n\n' "GAME: $gname_hr // VERSION: $version_basegame" > "$HOME/.magog/cdn_links.txt"

## get the cdn links for the individual parts ##

### basegame ### 
printf '\n%s\n%s\n%s\n\n' "============" " BASE GAME:" "============" >> "$HOME/.magog/cdn_links.txt"

## count number of parts and print the part number before the cdn-link
pc="1" ## <-- part-counter
tc="$(printf '%s\n' "$gparts_basegame"| wc -l)" ## <-- total-count
for part in $gparts_basegame; do
printf '%s\n' "(Part $pc of $tc)" >> "$HOME/.magog/cdn_links.txt"
get_cdn_link
pc="$((pc + 1))"
done

### dlc ###
[ -n "$gparts_dlc" ] && {
printf '\n\n%s\n%s\n%s\n\n' "======" " DLC:" "======" >> "$HOME/.magog/cdn_links.txt"
for part in $gparts_dlc; do
## get dlc title
printf '%s\n' "$game"| grep -B8 "$part"| grep -o -m1 '"title":.*'| cut -d '"' -f 4 >> "$HOME/.magog/cdn_links.txt"
get_cdn_link
done
}

### patches ###
[ -n "$gparts_patches" ] && {
printf '\n\n%s\n%s\n%s\n\n' "==========" " PATCHES:" "==========" >> "$HOME/.magog/cdn_links.txt"
for part in $gparts_patches; do
## get patch name
printf '%s\n' "$game"| grep -A1 "$part"| grep -o '"name":.*'| cut -d '"' -f 4 >> "$HOME/.magog/cdn_links.txt"
get_cdn_link
done
}
}


get_cdn_link () {
## fetch cdn-link for the $part in question
## NOTE: with every iteration, new cookies will be set, so we never need to worry about expiry,
## UNLESS the user doesn't request a game within 9 months or terminates the session (via web in this case)
sleep 0.4
curl -sLIb "$HOME/.magog/.gog-cookie.txt" -c "$HOME/.magog/.new_gog-cookie.txt" "https://www.gog.com/downloads/$part"| \
grep 'location'| grep -o 'https.*' >> "$HOME/.magog/cdn_links.txt"

## refresh gog cookie
refresh_gog_cookie

## print newline between links
printf '\n' >> "$HOME/.magog/cdn_links.txt"
}


display_cdn_links () {
## display the result 
cat "$HOME/.magog/cdn_links.txt"
}


get_gog_cookie () {
## get gog cookie, if it doesn't exist already.
[ ! -f "$HOME/.magog/.gog-cookie.txt" ] && {
## if ce.sh isn't available, get it
[ ! -f "$HOME/.magog/ce.sh" ] && curl -sLo "$HOME/.magog/ce.sh" "https://github.com/ConzZah/ce/raw/refs/heads/main/ce.sh"
[ -f "$HOME/.magog/ce.sh" ] && sh "$HOME/.magog/ce.sh" | grep -E 'gog_.*|gog-.*' > "$HOME/.magog/.gog-cookie.txt" || exit 1
}

## if 'gog-al' doesn't appear within '.gog-cookie.txt' then we're not logged in and need to abort.
! grep -q 'gog-al' "$HOME/.magog/.gog-cookie.txt" && printf '\n%s\n\n' "--> NOT LOGGED IN, LOGIN TO ANY GOG ACCOUNT IN FIREFOX AND TRY AGAIN." && \
{ rm -f "$HOME/.magog/.gog-cookie.txt"; exit 1 ;}

## if we're still running, return 0
return 0
}

refresh_gog_cookie () {
## make sure that '.new_gog-cookie.txt' becomes our current cookie
cat "$HOME/.magog/.new_gog-cookie.txt" > "$HOME/.magog/.gog-cookie.txt"
rm -f "$HOME/.magog/.new_gog-cookie.txt"
}


gog_library_indexer () {
get_gog_cookie
## obtain index of game id's and format them for processing
index="$(curl -sb "$HOME/.magog/.gog-cookie.txt" 'https://menu.gog.com/v1/account/licences' --compressed)"

## if $index contains 'Unable to authenticate', abort.
printf '%s\n' "$index"| grep -q 'Unable to authenticate' && \
printf '%s\n' "--> 	ERROR: 'Unable to authenticate'" && \
{ rm -f "$HOME/.magog/.gog-cookie.txt"; exit 1 ;}

## convert the output into a newline seperated list,
## so we can use it in the for loop 
index="$(printf '%s\n' "$index"| tr '[]",' ' '| tr -s ' '| tr ' ' '\n')"

## get the actual number of games on the gog account (gc = game-count)
gc="$(curl -sb "$HOME/.magog/.gog-cookie.txt" 'https://menu.gog.com/v1/account/stats'| \
tr ',' '\n'| grep -o 'games.*'| cut -d ':' -f 2)"

## if $gc is 0 or unset, then you don't have any games, or magog can't determine how many
[ "$gc" = "0" ] || [ -z "$gc" ] && printf '\n%s\n\n' "--> CAN'T GET NUMBER OF GAMES ON THIS GOG ACCOUNT." && \
{ rm -f "$HOME/.magog/.gog-cookie.txt"; exit 1 ;}

## show the user how many games they have
printf '\n%s\n\n' "--> GAMES ON THIS GOG ACCOUNT: $gc"

## set cg to 1 (cg = current-game)
cg="1"

## main loop to process them gamez
for game_id in $index; do

## show the user which game we're processing
printf '%s\n' "--> [${cg} // ${gc}]"

## check if $game_id is already in index.txt,
## if it isn't, proceed to add it.
! grep -q "$game_id" "$HOME/.magog/index.txt" && {

## get game details
game="$(curl -sb "$HOME/.magog/.gog-cookie.txt" -c "$HOME/.magog/.new_gog-cookie.txt" "https://www.gog.com/en/account/gameDetails/${game_id}.json" --compressed| sed 's#\\##g'| tr ',' '\n')"

## refresh gog cookie
refresh_gog_cookie

## get game title
game_title="$(printf '%s\n' "$game"| grep -m1 'title'| cut -d '"' -f 4| sed 's#,##g')"

## get game link
game_link="$(printf '%s\n' "$game"| grep -m1 -o "/downloads/.*"| cut -d '/' -f 3)"

## GENERATE INDEX ENTRY ( DELIM: '~' )
## INDEX MAP: 1 = $game_id ~ 2 = $game_title ~ 3 = $game_link
entry="${game_id}~${game_title}~${game_link}"

## write $entry to '$HOME/.magog/index.txt'
printf '%s\n' "$entry" >> "$HOME/.magog/index.txt"

## init vars before next iteration just to be safe
game=""; game_title=""; game_link=""; entry=""
sleep 0.4
}

## if $gc is equal to $cg, break out of the loop.
## (this means we have all of the games processed / reached the end)
[ "$gc" = "$cg" ]  && break

## increase $cg by 1
cg="$((cg + 1))"
done

## get rid of (the most common) unicode chars after the loop so we don't have to do it every iteration
sed -i -e 's#u0026##g' -e 's#u0027##g' -e 's#u2013##g' -e 's#u2019##g' -e 's#u2122##g' -e 's#u00ae##g' -e 's#u003C##g' -e 's#u003E##g' -e 's#u014d##g' "$HOME/.magog/index.txt"
}


### PRE-LAUNCH ###
## process arguments
while [ "$#" -gt "0" ]; do
case $1 in
## force a (re)index of the users gog-library
'-index'|'-INDEX'|'-i') gog_library_indexer; exit ;;

## NOTE: $game is only ever set once per run.
*) [ -z "$game" ] && { game="$1"; shift ;}
;;
esac
done

### LAUNCH ###
init
