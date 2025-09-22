#include "../../includes/am_types.h"

generic configuration FloodingC(int channel) {
   provides interface Flooding;
}

implementation {
    components FloodingP;
    Flooding = FloodingP.Flooding;

    components new TimerMilliC() as floodTimer;
    FloodingP.floodTimer -> floodTimer;

    components RandomC as Random;
    FloodingP.Random -> Random;

    components new AMSenderC(channel) as AMSender;
    FloodingP.AMSend -> AMSender;
    FloodingP.Packet -> AMSender;
    FloodingP.AMPacket -> AMSender;
}