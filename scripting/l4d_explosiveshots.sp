
#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "0.1-SNAPSHOT"
#define FCVAR_FLAGS FCVAR_NOTIFY

#define SND_EXPL1 "weapons/flaregun/gunfire/flaregun_explode_1.wav"
#define SND_EXPL2 "weapons/flaregun/gunfire/flaregun_fire_1.wav"
#define SND_EXPL3 "animation/plane_engine_explode.wav"

#define DEFAULT_CFG "data/l4d_explosiveshots.cfg"

ConVar g_cvAllow;
ConVar g_cvGameModes;
ConVar g_cvCurrGameMode;
ConVar g_cvCfgFile;

bool g_bPluginOn;
bool g_bL4D2;

public Plugin myinfo =
{
	name = "[L4D & L4D2] Explosive Shots",
	author = "Eärendil",
	description = "",
	version = PLUGIN_VERSION,
	url = "https://github.com//l4d_explosiveshots"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion ev = GetEngineVersion();
	if( ev == Engine_Left4Dead2 )
		g_bL4D2 = true;
	
	else if( ev != Engine_Left4Dead )
	{
		strcopy(error, err_max, "This plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}
		
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("l4d_explosiveshots_version", PLUGIN_VERSION, "Plugin version", FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_cvAllow = CreateConVar("l4d_expshots_enable", "1", "0 = Plugin off. 1 = Plugin on.", FCVAR_FLAGS, true, 0.0, true, 1.0);
	g_cvGameModes = CreateConVar("l4d_expshots_gamemodes", "","Enable the plugin in these gamemodes, separated by spaces. (Empty = all).", FCVAR_FLAGS);
	g_cvGameModes = CreateConVar("l4d_expshots_gamemodes", "","Enable the plugin in these gamemodes, separated by spaces. (Empty = all).", FCVAR_FLAGS);
	g_cvCfgFile = CreateConVar("l4d_expshots_configfile", DEFAULT_CFG, "Name of the config file to load", FCVAR_FLAGS);

	g_cvCurrGameMode = FindConVar("mp_gamemode");

	g_cvAllow.AddChangeHook(CVarChange_Enable);
	g_cvGameModes.AddChangeHook(CVarChange_Enable);
	g_cvCurrGameMode.AddChangeHook(CVarChange_Enable);
	g_cvCfgFile.AddChangeHook(CVarChange_Config);
}

public void OnConfigsExecuted()
{
	SwitchPlugin();
	LoadConfig();
}

void CVarChange_Enable(ConVar convar, const char[] oldValue, const char[] newValue)
{
	SwitchPlugin();
}

void CVarChange_Config(ConVar convar, const char[] oldValue, const char[] newValue)
{
	LoadConfig();
}

void SwitchPlugin()
{
	bool bAllow = g_cvAllow.BoolValue;
	if( !g_bPluginOn && bAllow && GetGameMode() )
	{
		g_bPluginOn = true;
		HookEvent("bullet_impact", Event_Bullet_Impact);
		PrintToServer("Plugin On");
	}
	if( g_bPluginOn && (!bAllow || !GetGameMode()) )
	{
		g_bPluginOn = false;
		UnhookEvent("bullet_impact", Event_Bullet_Impact);
		PrintToServer("Plugin Off");
	}
}

void LoadConfig()
{

}

bool GetGameMode()
{
	if( g_cvCurrGameMode == null )
		return false;
	
	char sGameModes[128], sGameMode[32];
	g_cvGameModes.GetString(sGameModes, sizeof(sGameModes));
	g_cvCurrGameMode.GetString(sGameMode, sizeof(sGameMode));

	if( !sGameModes[0] )
		return true;

	char sBuffer[32][32];
	int count = ExplodeString(sGameModes, ",",sBuffer, sizeof(sBuffer), sizeof(sBuffer[]));
	if( count == 0 )
		return true;

	for( int i = 0; i < count; i++ )
	{
		if( StrEqual(sBuffer[i], sGameMode) )
			return true;
	}
	return false;
}

Action Event_Bullet_Impact(Event event, const char[] name, bool dontBroadcast)
{
	return Plugin_Continue;
}