# NMRiH - Win Rates
Records and display winrate stats for every map played in a NMRiH server, inspired by Dayonn_dayonn, uses SQL threaded queries in order to avoid crashes and solves lots of bugs from before.

https://forums.alliedmods.net/showthread.php?p=2714046

![image](https://i.imgur.com/jJKgIP0.jpeg)
![image](https://i.imgur.com/hSr2Jsm.jpeg)

# Admin Commands (ROOT FLAG)
- `sm_delete_winrates`
  - Deletes all rows from database
- `sm_delete_player_winrates` <STEAM_1:0:0000000>
  - Deletes a player using STEAMID
- `sm_delete_map_winrates` <map_name>
  - Deletes a map by entering exact name


# CVars
- `sm_nmrih_winrates_enabled` (1/0) (Default: 1)
  - Enable or disable NMRiH Winrates
- `sm_nmrih_winrates_debug` (1/0) (Default: 0)
  - Will spam messages in console and log about any SQL action
- `sm_nmrih_winrates_database` (Default: nmrih_winrates)
  - Name of database keyvalue stored in sourcemod/configs/databases.cfg
- `sm_nmrih_winrates_table` (Default: winrates_table)
  - Name of table used by database previously defined

# Install
- Simply copy and merge /addons folder with the one in your game directory
- Edit `configs/winrates_exclude.cfg` --> Add excluded maps from plugin detection, won't be taken into account
- Edit `configs/databases.cfg` --> Insert a new keyvalue set like the following example:

`"nmrih_winrates"
{
   "driver" "sqlite"
   "database" "nmrih_winrates"
}`

- Inspired by Dayonn_dayonn plugin: https://forums.alliedmods.net/showthread.php?p=2578250
