#include "../../includes/am_types.h"

generic configuration NeighborDiscoveryC(int channel) {
   provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new TimerMilliC() as neighborTimer;
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components RandomC as Random;
    NeighborDiscoveryP.Random -> Random;

    components new AMSenderC(channel) as AMSender;
    NeighborDiscoveryP.AMSend -> AMSender;
    NeighborDiscoveryP.Packet -> AMSender;
    NeighborDiscoveryP.AMPacket -> AMSender;

    components new AMReceiverC(channel) as AMReceiver;
    NeighborDiscoveryP.Receive -> AMReceiver;
}