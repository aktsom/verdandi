// windows/ci/sc-smoke/SmokeNoBoot.sc: for the M0b smoke test only (never part of the product). norns's Crone class boots a SuperCollider server when sclang starts (Crone.bootOnInit), and a CI runner has no
// audio device: scsynth then fails to open the default PortAudio device, and sclang waits for the server for ever. this class switches the boot off after Crone's own initClass has run
// (StartUp reads the flag later), so that the smoke test compiles norns's classes without any realtime server.
SmokeNoBoot {
	*initClass {
		Class.initClassTree(Crone);
		Crone.bootOnInit = false;
	}
}
