#include <Timer.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"

module FloodingP {
   provides interface Flooding;

   uses interface Timer<TMilli> as floodTimer;
   uses interface AMSend;
   uses interface Packet;
   uses interface AMPacket;
   uses interface Random;
}

implementation {
    // Task declaration must come before usage
    task void flood();

    message_t packet;
    bool busy = FALSE;
    uint16_t seqNo = 0;

    command void Flooding.startFlooding() {
        // Start the flooding process with random initial delay
        if (!busy) {
            call floodTimer.startOneShot(100 + (call Random.rand16() % 400));
        }
    }

    command void Flooding.stopFlooding() {
        call floodTimer.stop();
    }

    event void floodTimer.fired() {
        dbg(FLOODING_CHANNEL, "Flooding timer fired\n");
        post flood();
    }

    task void flood() {
        if (!busy) {
            pack* msg = (pack*)(call Packet.getPayload(&packet, sizeof(pack)));
            if (msg == NULL) return;

            msg->src = TOS_NODE_ID;
            msg->dest = AM_BROADCAST_ADDR;
            msg->seq = ++seqNo;
            msg->TTL = 20;  // Allow reasonable network coverage
            msg->protocol = PROTOCOL_FLOOD;

            if (call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(pack)) == SUCCESS) {
                busy = TRUE;
                dbg(FLOODING_CHANNEL, "Flooding packet sent with seqNo: %d\n", seqNo);
            } else {
                dbg(FLOODING_CHANNEL, "Flooding packet send failed\n");
            }
        }
    }

    event void AMSend.sendDone(message_t* msg, error_t err) {
        if (&packet == msg) {
            busy = FALSE;
        }
    }
}