#!/usr/bin/env sh

### /// magog.sh // ConzZah // 2026-10-18 07:15 ///

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

## if the user did provide anything via arguments, assign it to $game
game=""
[ -n "$1" ] && game="$1"

## if $game is still empty, launch fzf, so the user can choose from their library INTERACTIVELY
[ -z "$game" ] && {
chosen_game=""
chosen_game="$(cut -d '~' -f 2 < "$HOME/.magog/index.txt"| fzf --header "--> CHOOSE A GAME")"

## if $chosen_game was empty, then no game was chosen
[ -z "$chosen_game" ] && printf '\n%s\n\n' "--> NO GAME CHOSEN." && exit 1

## if $chosen_game is NOT empty, get the full index line(s)
[ -n "$chosen_game" ] && game="$(grep "$chosen_game" "$HOME/.magog/index.txt")" 
}

## if the $game is a gog link, make sure only the game name remains & call get_gog_links
printf '%s\n' "$game"| grep -q 'https://www.gog.com/.*/game/.*' && \
game="$(printf '%s\n' "$game"| cut -d '/' -f 6)" && \
{ get_gog_links; display_cdn_links; exit ;}

## if the $game is just the game name, call get_gog_links
[ -n "$game" ] && { get_gog_links; display_cdn_links; exit ;}
}


get_gog_links () {
## if the specified $game is not found in index.txt, evac
! game="$(grep -i "$game" "$HOME/.magog/index.txt")" && \
printf '\n%s\n\n' "--> ERROR: GAME: '$game' IS NOT IN INDEX" && exit 1

## if we have more than one line in $game, 
## launch fzf for the user to choose one of them INTERACTIVELY
chosen_game=""
[ "$(printf '%s\n' "$game"| wc -l)"  -gt "1" ] && {
chosen_game="$(printf '%s\n' "$game"| cut -d '~' -f 2| fzf --header "--> CHOOSE A GAME")"

## if $chosen_game was empty, then no game was chosen (shocker, i know..)
[ -z "$chosen_game" ] && printf '\n%s\n\n' "--> NO GAME CHOSEN." && exit 1

## if $chosen_game is NOT empty, get the full index line(s)
[ -n "$chosen_game" ] && game="$(printf '%s\n' "$game" |grep "$chosen_game")"
}

## get game name
gname_hr="$(printf '%s\n' "$game"| cut -d '~' -f 2)"
printf '\n%s\n\n' "GAME: $gname_hr" > "$HOME/.magog/cdn_links.txt"

## get the part numbers
gparts_basegame="$(printf '%s\n' "$game"| cut -d '~' -f 4| tr ',' '\n')"
gparts_patches="$(printf '%s\n' "$game"| cut -d '~' -f 6 | tr ',' '\n')"
gparts_dlc="$(printf '%s\n' "$game"| cut -d '~' -f 5 | tr ',' '\n')"

## tell the user to not be impatient
printf '\n%s\n\n' "--> GENERATING CDN-LINKS FOR: '$gname_hr' PLEASE WAIT.."

## get the cdn links for the individual parts
## basegame
printf '\n%s\n%s\n%s\n\n' "============" " BASE GAME:" "============" >> "$HOME/.magog/cdn_links.txt"
for part in $gparts_basegame; do
get_cdn_link
done

## dlc
[ -n "$gparts_dlc" ] && {
printf '\n\n%s\n%s\n%s\n\n' "======" " DLC:" "======" >> "$HOME/.magog/cdn_links.txt"
for part in $gparts_dlc; do
get_cdn_link
done
}

## patches
[ -n "$gparts_patches" ] && {
printf '\n\n%s\n%s\n%s\n\n' "==========" " PATCHES:" "==========" >> "$HOME/.magog/cdn_links.txt"
for part in $gparts_patches; do
get_cdn_link
done
}
}


get_cdn_link () {
## fetch cdn-link for the $part in question
## NOTE: with every iteration, new cookies will be set, so we never need to worry about expiry,
## UNLESS the user doesn't request a game within 9 months or terminates the session (via web in this case)
sleep 0.5
curl -sLIb "$HOME/.magog/.gog-cookie.txt" -c "$HOME/.magog/.new_gog-cookie.txt" "https://www.gog.com/downloads/$part"| \
grep 'location'| grep -o 'https.*' >> "$HOME/.magog/cdn_links.txt"

## make sure that the new cookie becomes our current cookie
cat "$HOME/.magog/.new_gog-cookie.txt" > "$HOME/.magog/.gog-cookie.txt"
rm -f "$HOME/.magog/.new_gog-cookie.txt"

## print newline (mandatory)
printf '\n' >> "$HOME/.magog/cdn_links.txt"
}


display_cdn_links () {
## display the result 
cat "$HOME/.magog/cdn_links.txt"
}


gog_library_indexer () {
## remove 'index.txt', just to be safe
rm -f "$HOME/.magog/index.txt" >/dev/null

## get gog cookie
## if ce.sh isn't available, get it
[ ! -f "$HOME/.magog/ce.sh" ] && curl -sLo "$HOME/.magog/ce.sh" "https://github.com/ConzZah/ce/raw/refs/heads/main/ce.sh"
[ -f "$HOME/.magog/ce.sh" ] && sh "$HOME/.magog/ce.sh" | grep -E 'gog_.*|gog-.*' > "$HOME/.magog/.gog-cookie.txt" || exit 1

## if 'gog-al' doesn't appear within '.gog-cookie.txt' then we're not logged in and need to abort.
! grep -q 'gog-al' "$HOME/.magog/.gog-cookie.txt" && printf '\n%s\n\n' "--> NOT LOGGED IN, LOGIN TO ANY GOG ACCOUNT IN FIREFOX AND TRY AGAIN." && exit 1

## obtain index of game id's and format them for processing
index="$(curl -sb "$HOME/.magog/.gog-cookie.txt" 'https://menu.gog.com/v1/account/licences' --compressed)"

## if $index contains '504 Gateway Time-out', abort.
printf '%s\n' "$index"| grep -q '504 Gateway Time-out' && \
printf '%s\n' "--> 	ERROR: 504, TRY AGAIN LATER." && exit 1

## convert the output into a newline seperated list,
## so we can use it in the for loop 
index="$(printf '%s\n' "$index"| tr '[]",' ' '| tr -s ' '| tr ' ' '\n')"

## get the actual number of games on the gog account (gc = game-count)
gc="$(curl -sb "$HOME/.magog/.gog-cookie.txt" 'https://menu.gog.com/v1/account/stats'| \
tr ',' '\n'| grep -o 'games.*'| cut -d ':' -f 2)"

## if $gc is 0, then we don't have any games.
[ "$gc" = "0" ] && printf '\n%s\n\n' "--> THERE ARE NO GAMES ON THIS GOG ACCOUNT, GO BUY SOME.." && exit 1

## show the user how many games they have
printf '\n%s\n\n' "--> $gc GAMES FOUND"

## set cg to 1 (cg = current-game)
cg="1"

## main loop to process them gamez
for game_id in $index; do

## show the user which game we're processing
printf '%s\n' "--> [${cg} // ${gc}]"

## get game details
game="$(curl -sb "$HOME/.magog/.gog-cookie.txt" "https://www.gog.com/en/account/gameDetails/${game_id}.json" --compressed| sed 's#\\##g'| tr ',' '\n')"

## get game title
game_title="$(printf '%s\n' "$game"| grep -m1 title| cut -d '"' -f 4| sed 's#,##g')"

## get game link
game_link="$(printf '%s\n' "$game"| grep -m1 -o "/downloads/.*"| cut -d '/' -f 3)"

## get list of part numbers of basegames, dlcs & patches, while omitting the easy-installers
part_list_complete="$(printf '%s\n' "$game"| grep -o '/downloads/.*'| sed -e 's#"##g' -e 's#/downloads/##g' -e's#,$##g' -e '$d')"
part_list_basegame="$(printf '%s\n' "$part_list_complete"| grep -o "$game_link/en1installer.*"| tr '\n' ','| sed 's#,$##g')"
part_list_dlc="$(printf '%s\n' "$game"| grep '.*DLC.*' -B1| grep -o 'manualUrl.*'| cut -d '/' -f 3-4| tr '\n' ','| sed -e 's#"##g' -e 's#,$##')"
part_list_patches="$(printf '%s\n' "$part_list_complete"| grep -o '.*en1patch.*'| tr '\n' ','| sed 's#,$##g')"

## GENERATE INDEX ENTRY (DELIM: ~)
## INDEX MAP: 1 = $game_id ~ 2 = $game_title ~ 3 = $game_link ~ 4 = $part_list_basegame ~ 5 = $part_list_dlc ~ 6 = $part_list_patches
entry="$game_id~$game_title~$game_link~$part_list_basegame~$part_list_dlc~$part_list_patches"

## write $entry to '$HOME/.magog/index.txt'
printf '%s\n' "$entry" >> "$HOME/.magog/index.txt"

## init vars before next iteration jus to be safe lol
game=""; game_title=""; game_link=""; part_list_complete=""; part_list_basegame=""; part_list_dlc=""; part_list_patches=""; entry=""
sleep 0.5

## if $gc is equal to $cg, break out of the loop.
## (this means we have all of the games processed / reached the end)
[ "$gc" = "$cg" ]  && break

## increase $cg by 1
cg="$((cg + 1))"
done

## get rid of (the most common) unicode chars after the loop so we don't have to do it every iteration
sed -i -e 's#u0026##g' -e 's#u0027##g' -e 's#u2013##g' -e 's#u2019##g' -e 's#u2122##g' -e 's#u00ae##g' -e 's#u003C##g' -e 's#u003E##g' -e 's#u014d##g' "$HOME/.magog/index.txt"

## check if we actually have all entries
[ "$(wc -l "$HOME/.magog/index.txt")" != "$gc" ] && \
printf '\n%s\n\n' "--> LINE-COUNT OF '$HOME/.magog/index.txt' DOESN'T MATCH: '$gc'" && exit 1
}


### PRE-LAUNCH ###
## process arguments
while [ "$#" = "1" ]; do
case $1 in
## force a (re)index of the users gog-library
'-index'|'-INDEX'|'-i') gog_library_indexer; exit ;;
*) ;;
esac
done

### LAUNCH ###
init "$@"
