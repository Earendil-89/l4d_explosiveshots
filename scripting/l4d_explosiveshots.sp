
#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <profiler>
#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "0.1-SNAPSHOT"
#define FCVAR_FLAGS FCVAR_NOTIFY
#define DEBUG 1

#define SND_EXPL1 "weapons/flaregun/gunfire/flaregun_explode_1.wav"
#define SND_EXPL2 "weapons/flaregun/gunfire/flaregun_fire_1.wav"
#define SND_EXPL3 "animation/plane_engine_explode.wav"

#define SERVER_TAG "[ExplosiveShots] "
#define DEFAULT_CFG "data/l4d_explosiveshots.cfg"

#define WEAPON_COUNT_L2 18
#define WEAPON_COUNT_L1 7

static char g_sExplosionProps[][] = { "dmg", "scaleff", "radius", "stun_special", "stun_witch", "stun_tank", "enabled" };

enum struct WeaponSettings
{
	float Damage;
	float FriendDamage;
	float Radius;
	float StunSpecial;
	float StunWitch;
	float StunTank;
	bool Enabled;
}

// Stores the behaviour of client shots
enum ClientExplosion
{
	Mode_Block,	// Clients can't cause explosions
	Mode_Auto,	// Clients will cause explosions with weapons allowed in the cfg file
	Mode_Force	// Clients will cause explosions with any gun
};

ConVar g_cvAllow;
ConVar g_cvGameModes;
ConVar g_cvCurrGameMode;
ConVar g_cvCfgFile;

bool g_bPluginOn;
bool g_bL4D2;

ClientExplosion g_ceClientMode[MAXPLAYERS + 1] = { Mode_Auto, ... };	// Stores the shot behaviour
bool g_bClientAllow[MAXPLAYERS + 1] = {true, ... };	// Blocks shots of client, used to prevent multiple explosions in 1 shot due to piercing

WeaponSettings g_esWeaponSettings[WEAPON_COUNT_L2];

StringMap g_smWeapons;

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

public void OnClientConnected(int client)
{
	g_ceClientMode[client] = Mode_Auto;
	g_bClientAllow[client] = true;
}

public void OnClientDisconnect(int client)
{
	g_ceClientMode[client] = Mode_Auto;
	g_bClientAllow[client] = true;
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
	}
	if( g_bPluginOn && (!bAllow || !GetGameMode()) )
	{
		g_bPluginOn = false;
		UnhookEvent("bullet_impact", Event_Bullet_Impact);
	}
}

void LoadConfig()
{
	char sFileName[64];
	g_cvCfgFile.GetString(sFileName, sizeof(sFileName));
	#if DEBUG
	PrintToServer("%sReading configs for \"%s\".", SERVER_TAG, sFileName);
	#endif

	if( !ReadCfgFile(sFileName) )
		SetFailState("Errors on config files.");
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

/* ============================================================================= *
 *                                  FileReader                                   *
 * ============================================================================= */
/**
 * Attempts to read the provided config file, if the file is custom and fails to
 * read, it will open the default one.
 * 
 * @param fileName     Relative path of the cfg file
 * @return             true on success false on fail
 */
bool ReadCfgFile(const char[] fileName)
{
	// Build the file path
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), fileName);
	bool bDefault = ( strncmp(fileName, DEFAULT_CFG, 27) == 0 ) ? true : false; // Check if is the default file

	if( !FileExists(sPath) )	// Throw warning/error if file doesn't exist.
	{
		if( !bDefault )
		{
			PrintToServer("%sWarning: Missing config file \"%s\", attempting default file.", SERVER_TAG, fileName);
			return ReadCfgFile(DEFAULT_CFG);	// Attempt to read default file
		}
		PrintToServer("%sError: Missing default config file, plugin disabled.", SERVER_TAG);
		return false;	// Crash plugin
	}

	KeyValues hKV = new KeyValues("explosions");
	if( !hKV.ImportFromFile(sPath) )	// Throw warning/error if file can't be opened
	{
		if( !bDefault )
		{
			PrintToServer("%sWarning: Can't read \"%s\", attempting default file.", SERVER_TAG, fileName);
			return ReadCfgFile(DEFAULT_CFG);		
		}
		PrintToServer("%sError: Can't read default config file, plugin disabled.", SERVER_TAG);
		return false;	
	}
	
	#if DEBUG
	PrintToServer("%sReading KeyValues file. Starting profiling.", SERVER_TAG);
	Profiler pro = new Profiler();
	pro.Start();
	#endif
	// Import the data into the defined ES and link each one with the StringMap
	delete g_smWeapons;
	g_smWeapons = CreateTrie();
	char sMainKey[12];
	sMainKey = g_bL4D2 ? "Left4Dead2" : "Left4Dead";

	if( !hKV.JumpToKey(sMainKey) )
	{
		if( !bDefault )
		{
			PrintToServer("%sWarning: Can't read \"%s\", attempting default file.", SERVER_TAG, fileName);
			return ReadCfgFile(DEFAULT_CFG);		
		}
		PrintToServer("%sError: Can't read default config file, plugin disabled.", SERVER_TAG);

		#if DEBUG
		delete pro;
		#endif
		return false;
	}
	hKV.GotoFirstSubKey();
	int count = 0;
	int max = g_bL4D2 ? WEAPON_COUNT_L2 : WEAPON_COUNT_L1;
	do
	{
		if( count >= max )	// This prevents going out of bounds of the ES array
		{
			count = 0;
			break;
		}

		char sName[32];
		hKV.GetSectionName(sName, sizeof(sName));
		g_smWeapons.SetValue(sName, count);
		#if DEBUG
		PrintToServer("%sKey %s", SERVER_TAG, sName);
		#endif

		for( int i = 0; i < sizeof(g_sExplosionProps); i++ )
		{
			if( !hKV.JumpToKey(g_sExplosionProps[i]) )
			{
				#if DEBUG
				delete pro;
				#endif
				delete hKV;

				if( !bDefault )
				{
					PrintToServer("%Warning: Failed to read \"%s\" value from \"%s\". Reading default file.", SERVER_TAG, g_sExplosionProps[i], sName);
					return ReadCfgFile(DEFAULT_CFG); 
				}
				PrintToServer("%sError: Failed to read \"%s\" value from \"%s\". Plugin disabled.", SERVER_TAG, g_sExplosionProps[i], sName); 
				delete hKV;
				return false;
			}

			switch( i )
			{
				case 0: g_esWeaponSettings[count].Damage = hKV.GetFloat(NULL_STRING);
				case 1: g_esWeaponSettings[count].FriendDamage = hKV.GetFloat(NULL_STRING);
				case 2: g_esWeaponSettings[count].Radius = hKV.GetFloat(NULL_STRING);
				case 3: g_esWeaponSettings[count].StunSpecial = hKV.GetFloat(NULL_STRING);
				case 4: g_esWeaponSettings[count].StunWitch = hKV.GetFloat(NULL_STRING);
				case 5: g_esWeaponSettings[count].StunTank = hKV.GetFloat(NULL_STRING);
				case 6: g_esWeaponSettings[count].Enabled = hKV.GetNum(NULL_STRING) == 1;
			}

			hKV.GoBack();
		}
		#if DEBUG
		PrintToServer("g_esWeaponSettings[%d].Damage =  %.4f", count, g_esWeaponSettings[count].Damage);
		PrintToServer("g_esWeaponSettings[%d].FriendDamage =  %.4f", count, g_esWeaponSettings[count].FriendDamage);
		PrintToServer("g_esWeaponSettings[%d].Radius =  %.4f", count, g_esWeaponSettings[count].Radius);
		PrintToServer("g_esWeaponSettings[%d].StunSpecial =  %.4f", count, g_esWeaponSettings[count].StunSpecial);
		PrintToServer("g_esWeaponSettings[%d].StunWitch =  %.4f", count, g_esWeaponSettings[count].StunWitch);
		PrintToServer("g_esWeaponSettings[%d].StunTank =  %.4f", count, g_esWeaponSettings[count].StunTank);
		PrintToServer("g_esWeaponSettings[%d].Enabled =  %b", count, g_esWeaponSettings[count].Enabled);
		#endif
		count++;
	}
	while( hKV.GotoNextKey(false) );

	if( count != max )
	{
		if( !bDefault )
		{
			PrintToServer("%sWarning: incorrect amount of weapon settigns provided. Opening default file.", SERVER_TAG);
			return ReadCfgFile(DEFAULT_CFG);
		}
		PrintToServer("%Error: incorrect amount of weapon settigns provided in default file. Plugin disabled.", SERVER_TAG);
		delete hKV;
		return false;
	}

	#if DEBUG
	PrintToServer("Key values read ended.");
	pro.Stop();
	PrintToServer("Profile ended, time: %.4f", pro.Time);
	delete pro;

	StringMapSnapshot sms = g_smWeapons.Snapshot();
	for( int i = 0; i < sms.Length; i++ )
	{
		char sKey[32];
		int value;
		sms.GetKey(i, sKey, sizeof(sKey));
		g_smWeapons.GetValue(sKey, value);
		PrintToServer("Key: %s; Value:%d", sKey, value);
	}
	#endif

	delete hKV;
	return true;
}

Action Event_Bullet_Impact(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	float vPos[3];
	vPos[0] = event.GetFloat("x");
	vPos[1] = event.GetFloat("y");
	vPos[2] = event.GetFloat("z");

	if( !g_bClientAllow[client] || IsFakeClient(client) )
		return Plugin_Continue;

	if( g_ceClientMode[client] == Mode_Block )
		return Plugin_Continue;
	
	char sWeapon[32];
	if( GetEntProp(client, Prop_Send, "m_usingMountedWeapon") == 1 )
		sWeapon = "minigun";

	else GetClientWeapon(client, sWeapon, sizeof(sWeapon));
	#if DEBUG
	PrintToServer("%sShot produced, weapon: %s", SERVER_TAG, sWeapon);
	#endif

	int index;
	if( !g_smWeapons.GetValue(sWeapon, index) )
	{
		#if DEBUG
		PrintToServer("%sFailed getting StringMap value!", SERVER_TAG);
		#endif
		return Plugin_Continue;
	}
	#if DEBUG
	PrintToServer("%sg_esWeaponSettings[index].Enabled: %b", SERVER_TAG, g_esWeaponSettings[index].Enabled);
	PrintToServer("%sg_ceClientMode[client] == Mode_Force: %b", SERVER_TAG, g_ceClientMode[client] == Mode_Force);
	#endif

	if( g_esWeaponSettings[index].Enabled || g_ceClientMode[client] == Mode_Force )
		CreateExplosion(client, vPos, g_esWeaponSettings[index].Damage, g_esWeaponSettings[index].Radius);

	return Plugin_Continue;
}

void CreateExplosion(int client, const float vPos[3], float dmg, float radius)
{
	// Convert floats into strings
	char sDmg[8], sRadius[8];
	Format(sDmg, sizeof(sDmg), "%.4f", dmg);
	Format(sRadius, sizeof(sRadius), "%.4f", radius);

	int entity = CreateEntityByName("env_explosion");
	#if DEBUG
	PrintToServer("%sCreating an explosion for client %d",SERVER_TAG, client);
	PrintToServer("%sEntity index: %d", SERVER_TAG, entity);
	PrintToServer("%sVector: %.2f, %.2f, %.2f", SERVER_TAG, vPos[0], vPos[1], vPos[2]);
	#endif

	TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
	DispatchKeyValue(entity, "iMagnitude", sDmg);
	if( radius > 0.0 ) DispatchKeyValue(entity, "iRadiusOverride", sRadius);
	DispatchKeyValue(entity, "rendermode", "5");
	DispatchKeyValue(entity, "spawnflags", "128");	// Random orientation
	DispatchKeyValue(entity, "fireballsprite", "sprites/zerogxplode.spr");
	SetEntPropEnt(entity, Prop_Data, "m_hInflictor", client);	// Make the player who created the env_explosion the owner of it
	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
	
	DispatchSpawn(entity);
	
	SetVariantString("OnUser1 !self:Explode::0.01:1)");	// Add a delay to allow explosion effect to be visible
	AcceptEntityInput(entity, "Addoutput");
	AcceptEntityInput(entity, "FireUser1");
	// env_explosion is autodeleted after 0.3s while spawnflag repeteable is not added
	
	g_bClientAllow[client] = false;
	RequestFrame(AllowShot_Frame, client);
	
	// Play an explosion sound
	switch( GetRandomInt(1,3) )
	{
		case 1: EmitAmbientSound(SND_EXPL1, vPos);
		case 2: EmitAmbientSound(SND_EXPL2, vPos);
		case 3: EmitAmbientSound(SND_EXPL2, vPos);
	}
}

void AllowShot_Frame(int client)
{
	g_bClientAllow[client] = true;
	#if DEBUG
	PrintToServer("%sEnabling client %d explosive shots.",SERVER_TAG, client);
	#endif
}