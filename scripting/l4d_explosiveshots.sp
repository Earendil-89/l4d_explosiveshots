#define DEBUG 0

#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <l4d_explosiveshots>
#include <survivorutilities>
#if DEBUG
#include <profiler>
#endif
#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "0.1-SNAPSHOT"
#define FCVAR_FLAGS FCVAR_NOTIFY

#define SND_EXPL1 "weapons/flaregun/gunfire/flaregun_explode_1.wav"
#define SND_EXPL2 "weapons/flaregun/gunfire/flaregun_fire_1.wav"
#define SND_EXPL3 "animation/plane_engine_explode.wav"

#define SERVER_TAG "[ExplosiveShots] "
#define DEFAULT_CFG "data/l4d_explosiveshots.cfg"

#define WEAPON_COUNT_L2 18
#define WEAPON_COUNT_L1 7

static char g_sExplosionProps[][] = { "dmg_zombies", "dmg_humans", "radius", "stun_special", "stun_witch", "stun_tank", "exp_chance", "enabled" };

enum struct WeaponSettings
{
	float DamageZombies;
	float DamageHumans;
	float Radius;
	float StunSpecial;
	float StunWitch;
	float StunTank;
	float Chance;
	bool Enabled;
}

ConVar g_cvAllow;
ConVar g_cvGameModes;
ConVar g_cvCurrGameMode;
ConVar g_cvCfgFile;

bool g_bPluginOn;
bool g_bL4D2;

int g_iMode[MAXPLAYERS + 1] = { Mode_Auto, ... };	// Stores the shot behaviour
bool g_bClientAllow[MAXPLAYERS + 1] = {true, ... };	// Blocks shots of client, used to prevent multiple explosions in 1 shot due to piercing

WeaponSettings g_esWeaponSettings[WEAPON_COUNT_L2];

StringMap g_smWeapons;

public Plugin myinfo =
{
	name = "[L4D & L4D2] Explosive Shots",
	author = "Eärendil",
	description = "Allows weapons to create explosions where bullet impacts.",
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
		
	CreateNative("L4D_ExplosiveShots_Set", Native_SetExplosiveShots);
	CreateNative("L4D_ExplosiveShots_Get", Native_GetExplosiveShots);

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

public void OnClientPutInServer(int client)
{
	g_iMode[client] = Mode_Auto;
	g_bClientAllow[client] = true;
	if( g_bPluginOn )
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if( !g_bPluginOn )
		return;

	if( strncmp(classname, "witch", 5) == 0 )
		SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_Witch);
}

public void OnClientDisconnect(int client)
{
	g_iMode[client] = Mode_Auto;
	g_bClientAllow[client] = true;
}

/* ============================================================================= *
 *                                   ConVars                                     *
 * ============================================================================= */

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
		HookEvent("player_death", Event_Player_Death);

		for( int i = 1; i <= MaxClients; i++ )
		{
			g_iMode[i] = Mode_Auto;
			if( IsClientInGame(i) )
				SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
				
		}

		int witch;
		while( (witch = FindEntityByClassname(witch, "witch")) != -1 )
			SDKHook(witch, SDKHook_OnTakeDamage, OnTakeDamage_Witch);
	}
	if( g_bPluginOn && (!bAllow || !GetGameMode()) )
	{
		g_bPluginOn = false;
		UnhookEvent("bullet_impact", Event_Bullet_Impact);
		UnhookEvent("player_death", Event_Player_Death);

		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsClientInGame(i) )
				SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage);
		}

		int witch = -1;
		while( (witch = FindEntityByClassname(witch, "witch")) != -1 )
			SDKHook(witch, SDKHook_OnTakeDamage, OnTakeDamage_Witch);
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
				case 0: g_esWeaponSettings[count].DamageZombies = hKV.GetFloat(NULL_STRING);
				case 1: g_esWeaponSettings[count].DamageHumans = hKV.GetFloat(NULL_STRING);
				case 2: g_esWeaponSettings[count].Radius = hKV.GetFloat(NULL_STRING);
				case 3: g_esWeaponSettings[count].StunSpecial = hKV.GetFloat(NULL_STRING);
				case 4: g_esWeaponSettings[count].StunWitch = hKV.GetFloat(NULL_STRING);
				case 5: g_esWeaponSettings[count].StunTank = hKV.GetFloat(NULL_STRING);
				case 6: g_esWeaponSettings[count].Chance = hKV.GetFloat(NULL_STRING);
				case 7: g_esWeaponSettings[count].Enabled = hKV.GetNum(NULL_STRING) == 1;
			}

			hKV.GoBack();
		}
		#if DEBUG
		PrintToServer("g_esWeaponSettings[%d].DamageZombies =  %.4f", count, g_esWeaponSettings[count].DamageZombies);
		PrintToServer("g_esWeaponSettings[%d].DamageHumans =  %.4f", count, g_esWeaponSettings[count].DamageHumans);
		PrintToServer("g_esWeaponSettings[%d].Radius =  %.4f", count, g_esWeaponSettings[count].Radius);
		PrintToServer("g_esWeaponSettings[%d].StunSpecial =  %.4f", count, g_esWeaponSettings[count].StunSpecial);
		PrintToServer("g_esWeaponSettings[%d].StunWitch =  %.4f", count, g_esWeaponSettings[count].StunWitch);
		PrintToServer("g_esWeaponSettings[%d].StunTank =  %.4f", count, g_esWeaponSettings[count].StunTank);
		PrintToServer("g_esWeaponSettings[%d].Chance = %.4f", count, g_esWeaponSettings[count].Chance);
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

/* ============================================================================= *
 *                          Events, SDKHooks & Frames                            *
 * ============================================================================= */

Action Event_Bullet_Impact(Event event, const char[] name, bool dontBroadcast)
{
	// Get owner of the bullet
	int client = GetClientOfUserId(event.GetInt("userid"));
	//Get origin of the impact
	float vPos[3];
	vPos[0] = event.GetFloat("x");
	vPos[1] = event.GetFloat("y");
	vPos[2] = event.GetFloat("z");

	// Ignore bots and prevent multiple explosions with one bullet
	if( !g_bClientAllow[client] || IsFakeClient(client) )
		return Plugin_Continue;

	// Ignore players blocked
	if( g_iMode[client] == Mode_Block )
		return Plugin_Continue;
	
	// Get the weapon name that caused the shot
	char sWeapon[32];
	if( GetEntProp(client, Prop_Send, "m_usingMountedWeapon") == 1 )
		sWeapon = "minigun";

	else GetClientWeapon(client, sWeapon, sizeof(sWeapon));
	#if DEBUG
	PrintToServer("%sShot produced, weapon: %s", SERVER_TAG, sWeapon);
	#endif

	// Get the index of the weapon properties using a StringMap
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
	PrintToServer("%sg_iMode[client] == Mode_Force: %b", SERVER_TAG, g_iMode[client] == Mode_Force);
	#endif

	if( g_iMode[client] == Mode_Auto )
	{
		if( g_esWeaponSettings[index].Enabled && ShouldCreateExplosion(g_esWeaponSettings[index].Chance) )
			CreateExplosion(client, vPos, g_esWeaponSettings[index].DamageZombies, g_esWeaponSettings[index].Radius);
	}
	else if( g_iMode[client] == Mode_Enable )
	{
		if( ShouldCreateExplosion(g_esWeaponSettings[index].Chance) )
			CreateExplosion(client, vPos, g_esWeaponSettings[index].DamageZombies, g_esWeaponSettings[index].Radius);
	}
	else if( g_iMode[client] == Mode_Force )
		CreateExplosion(client, vPos, g_esWeaponSettings[index].DamageZombies, g_esWeaponSettings[index].Radius);

	return Plugin_Continue;
}

Action Event_Player_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if( !client ) return Plugin_Continue; // Ignore zombies

	g_iMode[client] = Mode_Auto;
	return Plugin_Continue;
}

Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	// Ignore non-explosion damage and dmg caused by weapons
	if( damagetype != 64 || weapon != -1 )
		return Plugin_Continue;

	// Ignore damage from entities/wrold or non-survivors
	if( !IsValidClient(attacker) || GetClientTeam(attacker) != 2 )
		return Plugin_Continue;
		
	if( GetClientTeam(victim) == 3 ) // Zombie vitim of explosive shot
	{
		if( BlockStun(attacker, victim) )
		{
			damagetype = 0;	// Set Damagetype to generic to stop stunning
			return Plugin_Changed;
		}
		return Plugin_Continue;
	}
	// Past this line only other option is a survivor
	if( SetFriendlyFire(attacker, victim, damage, damagePosition) )
		SDKHooks_TakeDamage(victim, attacker, attacker, damage, DMG_BULLET|DMG_SLASH|DMG_DIRECT);
	else
		return Plugin_Handled;

	return Plugin_Continue;
}

Action OnTakeDamage_Witch(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if( damagetype != 64 || weapon != -1 )
		return Plugin_Continue;

	if( !IsValidClient(attacker) || GetClientTeam(attacker) != 2 )
		return Plugin_Continue;

	if( BlockStun(attacker, victim, true) )
	{
		damagetype = 0;	// Set Damagetype to generic to stop stunning
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

void AllowShot_Frame(int client)
{
	g_bClientAllow[client] = true;
	#if DEBUG
	PrintToServer("%sEnabling client %d explosive shots.",SERVER_TAG, client);
	#endif
}

/* ============================================================================= *
 *                                   Functions                                   *
 * ============================================================================= */

/**
 * Creates an env_explosion to destroy objects, push physics and hurt/knock players and zombies
 * It doesn't hurt survivors, only zombies/entities, so it will need to be fixed later
 */
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

/**
 * Determines if the zombie should be stunned
 * Gets the weapon info of the player and then decides based on a random number
 * if should be stunned or not
 */
bool BlockStun(int client, int zombie, bool isWitch = false)
{
	// Get the client weapon
	char sWeapon[32];
	if( GetEntProp(client, Prop_Send, "m_usingMountedWeapon") == 1 )
		sWeapon = "minigun";

	else GetClientWeapon(client, sWeapon, sizeof(sWeapon));
	// Get the weapon properties using HashMaps
	int index;
	if( !g_smWeapons.GetValue(sWeapon, index) )
		return false;	// Error getting weapon
	
	// Get the chance of stunning the infected based on the zombie
	float chance;
	if( isWitch ) chance = g_esWeaponSettings[index].StunWitch;
	else chance = GetEntProp(zombie, Prop_Send, "m_zombieClass") == 8 ?
		g_esWeaponSettings[index].StunTank : g_esWeaponSettings[index].StunSpecial;

	if( chance <= 0.0 ) return false;

	return chance >= GetRandomFloat(0.0, 1.0);
}

bool ShouldCreateExplosion(float chance)
{
	if( chance <= 0.0 ) {
		return false;
	}
	return chance >= GetRandomFloat(0.0, 1.0);
}
/**
 * Determines if a survivor can receive friendly fire from explosive shots and sets the damage
 * If no ff should be applied, then returns false
 */
bool SetFriendlyFire(int client, int victim, float &damage, const float origin[3])
{
	// Get the client weapon
	char sWeapon[32];
	if( GetEntProp(client, Prop_Send, "m_usingMountedWeapon") == 1 )
		sWeapon = "minigun";

	else GetClientWeapon(client, sWeapon, sizeof(sWeapon));

	int index;
	if( !g_smWeapons.GetValue(sWeapon, index) )
		return false;	// Error getting weapon

	if( g_esWeaponSettings[index].DamageHumans <= 0.0 )
		return false;

	// Get the distance between victim and damage origin
	float vPos[3], distance;
	GetClientEyePosition(victim, vPos);
	vPos[2] -= 12;
	distance = GetVectorDistance(vPos, origin, false);

	if( g_esWeaponSettings[index].Radius > 0.0 )
		damage = g_esWeaponSettings[index].DamageHumans - (g_esWeaponSettings[index].DamageHumans / g_esWeaponSettings[index].Radius) * distance;

	else
		damage = g_esWeaponSettings[index].DamageHumans - (0.4 * g_esWeaponSettings[index].DamageHumans * distance / g_esWeaponSettings[index].DamageZombies);
	
	// Sometimes low amount of damages will be produced, for instance if dmg is 0.9 survivor won't be hurt
	// So round to top or bottom with a chance depending how the fractional part is close to 0 or 1
	int integerPart = RoundToFloor(damage);
	float decimalPart = damage - integerPart;
	
	if( decimalPart <= 0.0 ) // Do nothing
		return true;

	if( decimalPart >= GetRandomFloat(0.0, 1.0) )
		damage += 1;

	return true;
}

bool IsValidClient(int client)
{
	if( !client || client > MaxClients )
		return false;

	return IsClientInGame(client);
}

/* ============================================================================= *
 *                                   Natives                                     *
 * ============================================================================= */

int Native_SetExplosiveShots(Handle plugin, int numParams)
{
	if( !g_bPluginOn )
		return false;

	int client = GetNativeCell(1);
	int mode = GetNativeCell(2);

	if( !client || client > MaxClients )
		ThrowNativeError(SP_ERROR_INDEX, "Client index %d is invalid.", client);

	if( !IsClientInGame(client) )
		ThrowNativeError(SP_ERROR_PARAM, "Client %d is not in game.", client);

	if( GetClientTeam(client) != 2 )
		ThrowNativeError(SP_ERROR_PARAM, "Client %d is not survivor.", client);

	if( !IsPlayerAlive(client) )
		ThrowNativeError(SP_ERROR_PARAM, "Client %d is dead.", client);
	
	if( mode >= Mode_Block && mode <= Mode_Force )
	{
		PrintToServer("%d, %d", mode, Mode_Block);
		g_iMode[client] = mode;
		return true;
	}
	else 
		ThrowNativeError(SP_ERROR_PARAM, "Invalid mode provided.");
	
	return false;
}

int Native_GetExplosiveShots(Handle plugin, int numParams)
{
	if( !g_bPluginOn )
		return Mode_Disabled;

	int client = GetNativeCell(1);
	if( !client || client > MaxClients )
		ThrowNativeError(SP_ERROR_INDEX, "Client index %d is invalid.", client);

	if( !IsClientInGame(client) )
		ThrowNativeError(SP_ERROR_PARAM, "Client %d is not in game.", client);

	if( GetClientTeam(client) != 2 )
		ThrowNativeError(SP_ERROR_PARAM, "Client %d is not survivor.", client);

	if( !IsPlayerAlive(client) )
		ThrowNativeError(SP_ERROR_PARAM, "Client %d is dead.", client);

	return g_iMode[client];
}

