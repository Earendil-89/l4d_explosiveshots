#if defined _l4d_expshots_included
    #endinput
#endif
#define _l4d_expshots_included

public SharedPlugin __l4d_expshots =
{
    name = "l4d_explosiveshots"
    file = "l4d_explosiveshots.smx"
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __l4d_expshots_SetNTVOptional()
{
    MarkNativeAsOptional("L4D_ExplosiveShots_Set");
    MarkNativeAsOptional("L4D_ExplosivesShots_Get");
}
#endif

enum ExplosiveShotsMode
{
    Mode_Disabled,  // Just used as return, means that the plugin is disabled by convar or gamemode and won't perform any action
	Mode_Block,	    // Clients can't cause explosions
	Mode_Auto,  	// Clients will cause explosions with weapons allowed in the cfg file (DEFAULT)
    Mode_Enable,    // Clients will cause explosions with all weapons, but the chance of explosion is still controlled by plugin
	Mode_Force	    // Clients will cause explosions with all weapons and overrides explosion chance to 100%
};

/**
 * Sets the behaviour of explosive shots on a specific player.
 * 
 * @param client     Client to change the explosion mode
 * @param mode       Mode 
 * @return           Return description
 */
native bool L4D_ExplosiveShots_Set(int client, ExplosiveShotsMode mode);

/**
 * Returns the current explosive shots mode of a specific client
 * 
 * @param client     Client to check
 * @return           Mode_Disabled = Plugin disabled by convar or gamemode. Mode_Block = Cient can't perform explosive shots.
 *                   Mode_Auto = Controlled by plugin settings. Mode_Enable = All weapons can cause explosions but explosion chance still controlled by plugin
 *                   Mode_Force = Client will cause explosions with all weapons and with 100% chance.
 */
native ExplosiveShotsMode L4D_ExplosiveShots_Get(int client);