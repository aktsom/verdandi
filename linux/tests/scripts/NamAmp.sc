// the class that scripts such as princeton ship for the NamAmp plug-in (test copy of the interface: NamAmp.ar(in, active))
NamAmp : UGen {
    *ar { |in = 0, active = 1|
        ^this.multiNew('audio', in, active)
    }
}
