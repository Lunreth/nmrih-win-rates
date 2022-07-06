#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dbi>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_AUTHOR "Ulreth*"
#define PLUGIN_VERSION "1.0.4" // 6-07-2022
#define PLUGIN_NAME "[NMRiH] WinRates"
// CHANGELOG
/*
17-12-2020
- Increased limit for database storage (512 maps)
- Added limit for menu display (100 maps only to avoid critical bug)
- Fixed menu bug

1.0.2
- Fixed wrong NMS round lose condition check

1.0.3
- Fixed wrong syntax inside loading map rows
- Improved CFG key detection (map extensions not needed anymore)

1.0.4
- Fixed map list disappearing at random times
- Improved database connection method
*/
// CVARS
ConVar cvar_DatabaseName;
ConVar cvar_PluginEnabled;
ConVar cvar_DebugEnabled;
ConVar cvar_TableName;
// KEYVALUES
KeyValues hConfig;
// GLOBAL DATABASE VARIABLES
Database g_Database = null;
char g_MapName[48];
char g_DatabaseName[32];
char g_TableName[32];
// PLUGIN MAIN BOOL
bool g_PluginEnabled = true;
// MENU TEXT FROM DATABASE
char g_StringCurrentMapPlayer[10][64];
char g_StringCurrentMapOnline[64];
char g_StringCurrentMap[64];
char g_StringOnlineAllMaps[512][48];
char g_StringAllMaps[512][48];
// GLOBAL PLAYER STATS
char E_SteamID[10][72];
char g_SteamID[10][32];
char g_PlayerName[10][32];
// INTERNAL GLOBAL VARIABLES
int g_MapsCount;
int g_MapsCountOnline;
bool g_MapClear[10];
bool g_Warmup;

public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = "Records and display winrate stats for every map played in a NMRiH server, inspired by Dayonn_dayonn, uses threaded queries in order to avoid crashes.",
	version = PLUGIN_VERSION
};

public void OnPluginStart()
{
	LoadTranslations("nmrih_winrates.phrases");
	CreateConVar("sm_nmrih_winrates_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NONE);
	cvar_PluginEnabled = CreateConVar("sm_nmrih_winrates_enabled", "1.0", "Enable or disable NMRiH Winrates for maps", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_DebugEnabled = CreateConVar("sm_nmrih_winrates_debug", "0.0", "Will spam messages in console and log about any SQL action", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_DatabaseName = CreateConVar("sm_nmrih_winrates_database", "nmrih_winrates", "Name of database keyvalue stored in sourcemod/configs/databases.cfg");
	cvar_TableName = CreateConVar("sm_nmrih_winrates_table", "winrates_table", "Name of table used by database previously defined");
	AutoExecConfig(true, "nmrih_winrates");
	//OnMapStart()
	//OnConfigsExecuted()
	HookEvent("nmrih_practice_ending", Event_PracticeStart);
	HookEvent("game_restarting", Event_RoundStart);
	//HookEvent("nmrih_round_begin", Event_RoundBegin);
	//HookEvent("objective_complete", Event_ObjectiveComplete);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_leave", Event_PlayerLeave);
	//OnClientPostAdminCheck()
	HookEvent("player_extracted", Event_PlayerExtracted);
	//HookEvent("extraction_complete", Event_ExtractionEnd);
	HookEvent("state_change", Event_StateChange);
	//HookEvent("extraction_expire", Event_ExtractionEnd);
	//RegConsoleCmd("changelevel_next", Event_ChangeLevel);
	//RegConsoleCmd("changelevel", Event_ChangeLevel);
	//OnMapEnd()
	RegConsoleCmd("winrate", Menu_Main);
	RegConsoleCmd("winrates", Menu_Main);
	RegConsoleCmd("wr", Menu_Main);
	RegAdminCmd("sm_delete_winrates", Command_DeleteTable, ADMFLAG_ROOT);
	RegAdminCmd("sm_erase_winrates", Command_DeleteTable, ADMFLAG_ROOT);
	RegAdminCmd("sm_delete_player_winrates", Command_DeletePlayer, ADMFLAG_ROOT);
	RegAdminCmd("sm_erase_player_winrates", Command_DeletePlayer, ADMFLAG_ROOT);
	RegAdminCmd("sm_delete_map_winrates", Command_DeleteMap, ADMFLAG_ROOT);
	RegAdminCmd("sm_erase_map_winrates", Command_DeleteMap, ADMFLAG_ROOT);
}

public void OnMapStart()
{
	// ConVar Plugin Enabled
	g_PluginEnabled = true;
	if (GetConVarFloat(cvar_PluginEnabled) == 0.0)
	{
		g_PluginEnabled = false;
	}
	
	// Database connection
	if (g_PluginEnabled == false) return;
	cvar_DatabaseName.GetString(g_DatabaseName, sizeof(g_DatabaseName));
	Database.Connect(T_Connect, g_DatabaseName);
}

public void T_Connect(Database db, const char[] error, any data)
{
	if(db == null)
	{
		LogError("T_Connect returned invalid Database Handle");
		return;
	}
	g_Database = db;
	cvar_TableName.GetString(g_TableName, sizeof(g_TableName));
	char query[512];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS %s (steam_id TEXT, player_name TEXT, map_name TEXT, clear_count INTEGER, play_count INTEGER, clear_rate REAL);", g_TableName);
	db.Query(T_Generic, query);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] Connected to Database - Table winrate_players will be created in case this is fresh install.");
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] Connected to Database - Table winrate_players will be created in case this is fresh install.");
}

public void OnConfigsExecuted()
{
	if (g_PluginEnabled == false) return;
	
	GetCurrentMap(g_MapName, sizeof(g_MapName));
	
	// Disable plugin for certain maps using KeyValues CFG
	KeyValues hConfig = new KeyValues("winrates_exclude");
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/winrates_exclude.cfg");
	hConfig.ImportFromFile(path);
	
	// Jump into the first subsection
	if (!hConfig.GotoFirstSubKey())
	{
		PrintToServer("[NMRiH] Invalid CFG file, check full example at plugin download page");
		LogMessage("[NMRiH] Invalid CFG file, check full example at plugin download page");
	}
	
	// Iterate over subsections at the same nesting level
	char buffer[255];
	do
	{
		hConfig.GetSectionName(buffer, sizeof(buffer));
		if (StrContains(g_MapName, buffer, false) != -1)
		{
			g_PluginEnabled = false;
			PrintToServer("[WINRATES] Map excluded from winrates");
			LogMessage("[WINRATES] Map excluded from winrates");
			break;
		}
	} while(hConfig.GotoNextKey());
	
	delete hConfig;
}

public Action Command_DeleteTable(int client, int args)
{
	if (g_PluginEnabled == false) return Plugin_Handled;
	char query[512];
	Format(query, sizeof(query), "DROP TABLE IF EXISTS %s", g_TableName);
	g_Database.Query(T_Generic, query);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] Table deleted - Database winrate_nmrih is empty now.");
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] Table deleted - Database winrate_nmrih is empty now.");
	return Plugin_Handled;
}

public Action Command_DeletePlayer(int client, int args)
{
	if (g_PluginEnabled == false) return Plugin_Handled;
	if (args < 1)
	{
		PrintToConsole(client, "Usage: sm_deleteplayer <STEAM_1:0:0000000>");
		return Plugin_Handled;
	}
	char steam_id_erased[32];
	GetCmdArg(1, steam_id_erased, sizeof(steam_id_erased));
	char query[512];
	char escape_steam_id[72];
	g_Database.Escape(steam_id_erased, escape_steam_id, sizeof(escape_steam_id));
	Format(query, sizeof(query), "DELETE FROM %s WHERE steam_id = '%s';", g_TableName, escape_steam_id);
	g_Database.Query(T_Generic, query);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] Player deleted from database: %s", steam_id_erased);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] Player deleted from database: %s", steam_id_erased);
	return Plugin_Handled;
}

public Action Command_DeleteMap(int client, int args)
{
	if (g_PluginEnabled == false) return Plugin_Handled;
	if (args < 1)
	{
		PrintToConsole(client, "Usage: sm_deletemap <map_name>");
		return Plugin_Handled;
	}
	char map_erased[32];
	GetCmdArg(1, map_erased, sizeof(map_erased));
	char query[512];
	Format(query, sizeof(query), "DELETE FROM %s WHERE map_name = '%s';", g_TableName, map_erased);
	g_Database.Query(T_Generic, query);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] Map records erased from database: %s", map_erased);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] Map records erased from database: %s", map_erased);
	return Plugin_Handled;
}

public void OnClientPostAdminCheck(int client)
{
	if (g_PluginEnabled == false) return;
	if(!IsFakeClient(client))
	{
		g_MapClear[client] = false;
		GetCurrentMap(g_MapName, sizeof(g_MapName));
		GetClientAuthId(client, AuthId_Steam2, g_SteamID[client], sizeof(g_SteamID[]));
		if(g_Database == null)
		{
			return;
		}
		// SINGLE QUERY FOR CURRENT MAP
		char query[512];
		char escape_steam_id[72];
		g_Database.Escape(g_SteamID[client], escape_steam_id, sizeof(escape_steam_id));
		Format(query, sizeof(query), "SELECT * FROM %s WHERE steam_id = '%s' AND map_name = '%s';", g_TableName, escape_steam_id, g_MapName);
		g_Database.Query(T_LoadData, query, GetClientUserId(client));
		/*
		Database.Query will send the following to the threaded callback:
		Database = db
		Results = results
		*/
	}
}

public void T_LoadData(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_LoadData returned error: %s", error);
		return;
	}
	
	int client = GetClientOfUserId(data);
	if (client == 0)
	{
		return;
	}
	GetClientName(client, g_PlayerName[client], sizeof(g_PlayerName[]));
	int PlayerName_Col;
	int ClearCount_Col;
	int PlayCount_Col;
	int ClearRate_Col;
	results.FieldNameToNum("player_name", PlayerName_Col);
	results.FieldNameToNum("clear_count", ClearCount_Col);
	results.FieldNameToNum("play_count", PlayCount_Col);
	results.FieldNameToNum("clear_rate", ClearRate_Col);
    // Row found in table
	GetClientAuthId(client, AuthId_Steam2, g_SteamID[client], sizeof(g_SteamID[]));
	char query[512];
	char escape_player_name[72];
	if(results.FetchRow())
    {
		char DBPlayerName[32];
		results.FetchString(PlayerName_Col, DBPlayerName, sizeof(DBPlayerName));
		if (StrEqual(DBPlayerName,g_PlayerName[client]))
		{
			if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] Name of %s matches with DB.", g_PlayerName[client]);
			if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] Name of %s matches with DB.", g_PlayerName[client]);
		}
		else
		{
			if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] Updating name of %s", g_PlayerName[client]);
			if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] Updating name of %s", g_PlayerName[client]);
			db.Escape(g_PlayerName[client], escape_player_name, sizeof(escape_player_name));
			Format(query, sizeof(query), "UPDATE %s SET player_name = '%s' WHERE steam_id = '%s';", g_TableName, escape_player_name, g_SteamID[client]);
			db.Query(T_Generic, query);
		}
		int i_clear_count = results.FetchInt(ClearCount_Col);
		int i_play_count = results.FetchInt(PlayCount_Col);
		float i_clear_rate = results.FetchFloat(ClearRate_Col);
		Format(g_StringCurrentMapPlayer[client], sizeof(g_StringCurrentMapPlayer[]), "(  %s  )         --  (%1.f %%)  --  %d / %d", g_PlayerName[client], i_clear_rate, i_clear_count, i_play_count);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] Stats for %s successfully loaded.", g_PlayerName[client]);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] Stats for %s successfully loaded.", g_PlayerName[client]);
    }
	else
    {
		// Inserting new data
		db.Escape(g_PlayerName[client], escape_player_name, sizeof(escape_player_name));
		Format(g_StringCurrentMapPlayer[client], sizeof(g_StringCurrentMapPlayer[]), "(  %s  )         --  (0.00 %%)  --  0 / 0", g_PlayerName[client]);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] %s has no records in this map, creating new row in database.", g_PlayerName[client]);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] %s has no records in this map, creating new row in database.", g_PlayerName[client]);
		Format(query, sizeof(query), "INSERT INTO %s (steam_id, player_name, map_name, clear_count, play_count, clear_rate) VALUES ('%s', '%s', '%s', 0, 0, 0);", g_TableName, g_SteamID[client], escape_player_name, g_MapName);
		db.Query(T_Generic, query);
    }
	// ALL MAPS BY ONLINE PLAYERS DATA QUERY
	for (int i = 0; i < 10; i++)
	{
		// Some servers may not be full or have less than 9 slots, this avoids self injection too
		Format(E_SteamID[i], sizeof(E_SteamID[]), "x");
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			Format(g_SteamID[i], sizeof(g_SteamID[]), "x");
		}
		// Text requires special safety procedures to avoid injection
		g_Database.Escape(g_SteamID[i], E_SteamID[i], sizeof(E_SteamID[]));
	}
	Format(query, sizeof(query), "SELECT map_name, SUM(clear_count), SUM(play_count), SUM(clear_count)*100.0/SUM(play_count) FROM %s WHERE (steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s') GROUP BY map_name ORDER BY SUM(clear_count)*100.0/SUM(play_count) DESC;", g_TableName, E_SteamID[1], E_SteamID[2], E_SteamID[3], E_SteamID[4], E_SteamID[5], E_SteamID[6], E_SteamID[7], E_SteamID[8], E_SteamID[9]);
	g_Database.Query(T_LoadAllMapsOnline, query);
}

// ALL MAPS PLAYED BY ONLINE PLAYERS CALLBACK QUERY
public void T_LoadAllMapsOnline(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_LoadAllMapsOnline returned error: %s", error);
		return;
	}
	GetCurrentMap(g_MapName, sizeof(g_MapName));
	// Maps amount limited to 512 also for online players
	char i_map_name[48];
	g_MapsCountOnline = 0;
	while ((results.FetchRow()) && (g_MapsCountOnline <= 100))
	{
		results.FetchString(0, i_map_name, sizeof(i_map_name));
		int i_clear_count = results.FetchInt(1);
		int i_play_count = results.FetchInt(2);
		float i_clear_rate = results.FetchFloat(3);
		if (i_clear_count > 0)
		{
			if (StrEqual(i_map_name, g_MapName, false))
			{
				Format(g_StringOnlineAllMaps[g_MapsCountOnline], sizeof(g_StringOnlineAllMaps), "**%s | %.2f %% -- %d / %d", i_map_name, i_clear_rate, i_clear_count, i_play_count);
			}
			else
			{
				Format(g_StringOnlineAllMaps[g_MapsCountOnline], sizeof(g_StringOnlineAllMaps), "%s | %.2f %% -- %d / %d", i_map_name, i_clear_rate, i_clear_count, i_play_count);
			}
			g_MapsCountOnline++;
		}
	}
	// ALL DATA FROM THIS MAP
	char query[512];
	Format(query, sizeof(query), "SELECT SUM(clear_count), SUM(play_count), SUM(clear_count)*100.0/SUM(play_count) FROM %s WHERE map_name = '%s';", g_TableName, g_MapName);
	g_Database.Query(T_LoadMapData, query);
}

// THIS MAP DATA FROM ALL PLAYERS
public void T_LoadMapData(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_LoadMapData returned error: %s", error);
		return;
	}
	if (!results.FetchRow())
	{
		LogError("T_LoadMapData error found inside !results.FetchRow() method");
		return;
	}
	
	// Play count should be higher than 0
	if(results.IsFieldNull(1))
    {
		Format(g_StringCurrentMap, sizeof(g_StringCurrentMap), "(%t)  |  0.00 %%  --  0 / 0", "all_players");
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] Map %s has no records in DB.", g_MapName);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] Map %s has no records in DB.", g_MapName);
    }
	else
    {
		int i_map_clear_count = results.FetchInt(0);
		int i_map_play_count = results.FetchInt(1);
		float i_map_clear_rate = results.FetchFloat(2);
		Format(g_StringCurrentMap, sizeof(g_StringCurrentMap), "(%t)  |  %.2f %%  --  %d / %d", "all_players", i_map_clear_rate, i_map_clear_count, i_map_play_count);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] Stats for map %s successfully loaded.", g_MapName);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] Stats for map %s successfully loaded.", g_MapName);
    }
	// ONLINE PLAYERS CURRENT MAP QUERY
	for (int i = 0; i < 10; i++)
	{
		// Some servers may not be full or have less than 9 slots, this avoids self injection too
		Format(E_SteamID[i], sizeof(E_SteamID[]), "x");
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			Format(g_SteamID[i], sizeof(g_SteamID[]), "x");
		}
		// Text requires special safety procedures to avoid injection
		g_Database.Escape(g_SteamID[i], E_SteamID[i], sizeof(E_SteamID[]));
	}
	char query[512];
	Format(query, sizeof(query), "SELECT SUM(clear_count), SUM(play_count), SUM(clear_count)*100.0/SUM(play_count) FROM %s WHERE map_name = '%s' AND (steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s');", g_TableName, g_MapName, E_SteamID[1], E_SteamID[2], E_SteamID[3], E_SteamID[4], E_SteamID[5], E_SteamID[6], E_SteamID[7], E_SteamID[8], E_SteamID[9]);
	g_Database.Query(T_LoadMapDataOnline, query);
}

// THIS MAP RECORDS FROM ONLINE PLAYERS CALLBACK
public void T_LoadMapDataOnline(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_LoadMapDataOnline returned error: %s", error);
		return;
	}
	if (!results.FetchRow())
	{
		LogError("T_LoadMapDataOnline error found inside !results.FetchRow() method");
		return;
	}
	if(results.IsFieldNull(1))
	{
		Format(g_StringCurrentMapOnline, sizeof(g_StringCurrentMapOnline), "(%t)  |  0.00 %%  --  0 / 0", "online_players");
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] This map %s no previous record from any of online players.", g_MapName);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] This map %s has no previous record any of online players.", g_MapName);
	}
	else
	{
		int i_clear_count = results.FetchInt(0);
		int i_play_count = results.FetchInt(1);
		float i_clear_rate = results.FetchFloat(2);
		Format(g_StringCurrentMapOnline, sizeof(g_StringCurrentMapOnline), "(%t) | %.2f %%  --  %d / %d", "online_players", i_clear_rate, i_clear_count, i_play_count);
	}
	// ALL MAPS EVER RECORDED DATA QUERY
	char query[512];
	Format(query, sizeof(query), "SELECT map_name, SUM(clear_count), SUM(play_count), SUM(clear_count)*100.0/SUM(play_count) FROM %s WHERE play_count > 0 GROUP BY map_name ORDER BY SUM(clear_count)*100.0/SUM(play_count) DESC;", g_TableName);
	g_Database.Query(T_LoadAllMapsData, query);
}

// ALL MAPS EVER RECORDED CALLBACK QUERY
public void T_LoadAllMapsData(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_LoadAllMapsData returned error: %s", error);
		return;
	}
	GetCurrentMap(g_MapName, sizeof(g_MapName));
	char i_map_name[48];
	g_MapsCount = 0;
	while ((results.FetchRow()) && (g_MapsCount <= 100))
	{
		results.FetchString(0, i_map_name, sizeof(i_map_name));
		int i_clear_count = results.FetchInt(1);
		int i_play_count = results.FetchInt(2);
		float i_clear_rate = results.FetchFloat(3);
		if (i_clear_count > 0)
		{
			if (StrEqual(i_map_name, g_MapName, false))
			{
				Format(g_StringAllMaps[g_MapsCount], sizeof(g_StringAllMaps), "*%s | %.2f %% -- %d / %d", i_map_name, i_clear_rate, i_clear_count, i_play_count);
			}
			else
			{
				Format(g_StringAllMaps[g_MapsCount], sizeof(g_StringAllMaps), "%s | %.2f %% -- %d / %d", i_map_name, i_clear_rate, i_clear_count, i_play_count);
			}
			g_MapsCount++;
		}
	}
}

public Action Menu_Main(int client, int args)
{
	if (g_PluginEnabled == false) return Plugin_Handled;
	Menu hMenu = new Menu(Callback_Menu_Main, MENU_ACTIONS_ALL);
	char display[128];
	
	Format(display, sizeof(display), "[WinRates] \n Version: %s - Author: Ulreth \n", PLUGIN_VERSION);
	hMenu.SetTitle(display);
	
	Format(display, sizeof(display), "%T", "current_map", client);
	hMenu.AddItem("this_map", display, ITEMDRAW_DEFAULT);
	
	Format(display, sizeof(display), "%T", "online_players", client);
	hMenu.AddItem("rank_online", display, ITEMDRAW_DEFAULT);
	
	Format(display, sizeof(display), "%T", "all_players", client);
	hMenu.AddItem("rank_all", display, ITEMDRAW_DEFAULT);
	
	hMenu.AddItem("space", "",ITEMDRAW_SPACER);
	hMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int Callback_Menu_Main(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_DrawItem:
		{
			char info[32];
			int style;
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Select:
		{
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info));
			// 8-->9-->0
			if (StrEqual(info,"this_map"))			Menu_CurrentMap(param1);
			else if (StrEqual(info,"rank_online"))	Menu_Rank(param1);
			else if (StrEqual(info,"rank_all"))		Menu_RankAll(param1);
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
 	return 0;
}

public void Menu_CurrentMap(int client)
{
	if (g_PluginEnabled == false) return;
	Menu hMenu = new Menu(Callback_Menu_CurrentMap, MENU_ACTIONS_ALL);
	char display[512];
	Format(display, sizeof(display), "[WinRates] %T \n <Parameter>      --  <Win %%>  --  <Wins/Spawns>", "current_map", client);
	hMenu.SetTitle(display);
	// Current map winrates are loaded at map start
	hMenu.AddItem("average_current_map", g_StringCurrentMap, ITEMDRAW_DISABLED);
	hMenu.AddItem("average_current_map_online", g_StringCurrentMapOnline, ITEMDRAW_DISABLED);
	hMenu.AddItem("average_myself_current", g_StringCurrentMapPlayer[client], ITEMDRAW_DISABLED);
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_CurrentMap(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_Main(param1, 0);
		}
		case MenuAction_End:delete hMenu;
	}
	return 0;
}

public void Menu_Rank(int client)
{
	if (g_PluginEnabled == false) return;
	Menu hMenu = new Menu(Callback_Menu_Rank, MENU_ACTIONS_ALL);
	char display[512];
	Format(display, sizeof(display), "[WinRates] %T \n <Map name>       --  <Win %%>  --  <Wins/Spawns>", "online_players", client);
	hMenu.SetTitle(display);
	for (int i = 0; i < g_MapsCountOnline; i++)
	{
		hMenu.AddItem(g_StringOnlineAllMaps[i], g_StringOnlineAllMaps[i], ITEMDRAW_DISABLED);
	}
	if (hMenu.ItemCount == 0)
	{
		PrintToChat(client, "[WinRates] No previous records from online players were found.");
	}
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_Rank(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_Main(param1, 0);
		}
		case MenuAction_End:delete hMenu;
	}
	return 0;
}

public void Menu_RankAll(int client)
{
	if (g_PluginEnabled == false) return;
	Menu hMenu = new Menu(Callback_Menu_RankAll, MENU_ACTIONS_ALL);
	char display[512];
	Format(display, sizeof(display), "[WinRates] %T \n <Map name>       --  <Win %%>  --  <Wins/Spawns>", "all_players", client);
	hMenu.SetTitle(display);
	for (int i = 0; i < g_MapsCount; i++)
	{
		hMenu.AddItem(g_StringAllMaps[i], g_StringAllMaps[i], ITEMDRAW_DISABLED);
	}
	if (hMenu.ItemCount == 0)
	{
		PrintToChat(client, "[WinRates] No previous global records were found.");
	}
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_RankAll(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_Main(param1, 0);
		}
		case MenuAction_End:delete hMenu;
	}
	return 0;
}

public Action Event_PracticeStart(Event event, const char[] name, bool dontBroadcast)
{
	if (g_PluginEnabled == false) return Plugin_Continue;
	g_Warmup = true;
	return Plugin_Continue;
}
// CUIDADO CON ROUNDSTART - PARECE QUE NO SE EJECUTA
public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (g_PluginEnabled == false) return Plugin_Continue;
	if (g_Warmup == true)
	{
		g_Warmup = false;
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (IsPlayerAlive(i))
			{
				g_MapClear[i] = false;
			}
		}
	}
	return Plugin_Continue;
}
/*
public Action Event_RoundBegin(Event event, const char[] name, bool dontBroadcast)
{
	if (g_PluginEnabled == false) return Plugin_Continue;
	return Plugin_Continue;
}
*/
/*
public Action Event_ObjectiveComplete(Event event, const char[] name, bool dontBroadcast)
{
	if (g_PluginEnabled == false) return Plugin_Continue;
	return Plugin_Continue;
}
*/
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (g_PluginEnabled == false) return Plugin_Continue;
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	g_MapClear[client] = false;
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (g_PluginEnabled == false) return Plugin_Continue;
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if (g_Warmup == false)
	{
		GetClientAuthId(client, AuthId_Steam2, g_SteamID[client], sizeof(g_SteamID[]));
		char query[512];
		char escape_steam_id[72];
		g_Database.Escape(g_SteamID[client], escape_steam_id, sizeof(escape_steam_id));
		Format(query, sizeof(query), "UPDATE %s SET play_count = play_count+1, clear_rate = (CAST(clear_count AS REAL)/CAST(play_count+1 AS REAL))*100 WHERE map_name = '%s' AND steam_id = '%s';", g_TableName, g_MapName, escape_steam_id);
		g_Database.Query(T_Generic, query);
	}
	return Plugin_Continue;
}

public Action Event_PlayerLeave(Event event, const char[] name, bool dontBroadcast)
{
	if (g_PluginEnabled == false) return Plugin_Continue;
	int client = GetEventInt(event, "index");
	g_MapClear[client] = false;
	// ALL MAPS BY ONLINE PLAYERS DATA QUERY
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			Format(g_SteamID[i], sizeof(g_SteamID[]), "x");
		}
		// Text requires special safety procedures to avoid injection
		g_Database.Escape(g_SteamID[i], E_SteamID[i], sizeof(E_SteamID[]));
	}
	char query[512];
	Format(query, sizeof(query), "SELECT map_name, SUM(clear_count), SUM(play_count), SUM(clear_count)*100.0/SUM(play_count) FROM %s WHERE (steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s' OR steam_id = '%s') GROUP BY map_name ORDER BY SUM(clear_count)*100.0/SUM(play_count) DESC;", g_TableName, E_SteamID[1], E_SteamID[2], E_SteamID[3], E_SteamID[4], E_SteamID[5], E_SteamID[6], E_SteamID[7], E_SteamID[8], E_SteamID[9]);
	g_Database.Query(T_LoadAllMapsOnline, query);
	return Plugin_Continue;
}

public Action Event_PlayerExtracted(Event event, const char[] name, bool dontBroadcast)
{
	if (g_PluginEnabled == false) return Plugin_Continue;
	int client = GetEventInt(event, "player_id");
	GetClientAuthId(client, AuthId_Steam2, g_SteamID[client], sizeof(g_SteamID[]));
	g_MapClear[client] = true;
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] %s reached extraction point, added 1 point to clear count variable.", g_PlayerName[client]);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] %s reached extraction point, added 1 point to clear count variable.", g_PlayerName[client]);
	char query[512];
	char escape_steam_id[72];
	g_Database.Escape(g_SteamID[client], escape_steam_id, sizeof(escape_steam_id));
	Format(query, sizeof(query), "UPDATE %s SET play_count = play_count+1, clear_count = clear_count+1, clear_rate = (CAST(clear_count+1 AS REAL)/CAST(play_count+1 AS REAL))*100 WHERE steam_id = '%s' AND map_name = '%s';", g_TableName, escape_steam_id, g_MapName);
	g_Database.Query(T_Generic, query);
	return Plugin_Continue;
}

public void Event_StateChange(Event event, const char[] name, bool dontBroadcast)
{
	//net_showevents 2 + developer 2
	if (g_PluginEnabled == false) return;
	int obj_state = GetEventInt(event, "state"); // Different values for each game type
	int game_type = GetEventInt(event, "game_type"); // 0 = NMO | 1 = NMS
	/*
	[SHARED VALUES]
	Practice round = 1
	Round start = 2
	Round running = 3
	
	[NMS game_type 1]
	¿Map win = 4?
	Round lost = 5
	Restart = 6
	
	[NMO game_type 0]
	Map win = 5
	Round lost = 6
	Restart = 7
	*/
	if (obj_state == 5)
	{
		// Round lost
		if (game_type == 1)
		{
			AlivePlayersLose();
		}
		// Map win
		if (game_type == 0)
		{
			// ALIVE PLAYERS WIN
			for (int i = 1; i <= MaxClients; i++)
			{
				if (g_MapClear[i] == false)
				{
					if (IsClientInGame(i))
					{
						if (IsPlayerAlive(i))
						{
							g_MapClear[i] = true;
							GetClientAuthId(i, AuthId_Steam2, g_SteamID[i], sizeof(g_SteamID[]));
							if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] %s is alive and reached extraction.", g_PlayerName[i]);
							if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] %s is alive and reached extraction.", g_PlayerName[i]);
							char query[512];
							char escape_steam_id[72];
							g_Database.Escape(g_SteamID[i], escape_steam_id, sizeof(escape_steam_id));
							Format(query, sizeof(query), "UPDATE %s SET play_count = play_count+1, clear_count = clear_count+1, clear_rate = (CAST(clear_count AS REAL)/CAST(play_count+1 AS REAL))*100 WHERE steam_id = '%s' AND map_name = '%s';", g_TableName, escape_steam_id, g_MapName);
							g_Database.Query(T_Generic, query);
						}
					}
				}
			}
		}
	}
}

public void Event_ExtractionEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_PluginEnabled == false) return;
	AlivePlayersLose();
}

public void AlivePlayersLose()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_MapClear[i] == false)
		{
			if (IsClientInGame(i))
			{
				if (IsPlayerAlive(i))
				{
					GetClientAuthId(i, AuthId_Steam2, g_SteamID[i], sizeof(g_SteamID[]));
					if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[SQL WinRate] %s is alive but round ended and never reached extraction.", g_PlayerName[i]);
					if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[SQL WinRate] %s is alive but round ended and never reached extraction.", g_PlayerName[i]);
					char query[512];
					char escape_steam_id[72];
					g_Database.Escape(g_SteamID[i], escape_steam_id, sizeof(escape_steam_id));
					Format(query, sizeof(query), "UPDATE %s SET play_count = play_count+1, clear_rate = (CAST(clear_count AS REAL)/CAST(play_count+1 AS REAL))*100 WHERE steam_id = '%s' AND map_name = '%s';", g_TableName, escape_steam_id, g_MapName);
					g_Database.Query(T_Generic, query);
				}
			}
		}
	}
}

// GENERIC CALLBACK FOR THREADED QUERY
public void T_Generic(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_Generic returned error: %s", error);
		return;
	}
}