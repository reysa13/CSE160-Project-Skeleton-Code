#include <Timer.h>
#include "../../includes/am_types.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"

module NeighborDiscoveryP {
   provides interface NeighborDiscovery;

   uses interface Timer<TMilli> as neighborTimer;
   uses interface Random;
   uses interface AMSend;
   uses interface Receive;
   uses interface Packet;
   uses interface AMPacket;
}

implementation {
   // Task declaration must come before usage
   task void search();

   typedef nx_struct neighbor_entry {
       nx_uint16_t id;
       nx_uint32_t lastSeen;
   } neighbor_entry_t;

   neighbor_entry_t neighbors[20];  // Fixed size for simplicity
   uint8_t neighborCount = 0;
   message_t packet;
   bool busy = FALSE;

   void sendPing() {
       if (!busy) {
           pack* msg = (pack*)(call Packet.getPayload(&packet, sizeof(pack)));
           if (msg == NULL) return;

           msg->src = TOS_NODE_ID;
           msg->dest = AM_BROADCAST_ADDR;
           msg->seq = 0;
           msg->TTL = 1;
           msg->protocol = PROTOCOL_PING;

           if (call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(pack)) == SUCCESS) {
               busy = TRUE;
           }
       }
   }

    command void NeighborDiscovery.start() {
        // Start the neighbor discovery process
        call neighborTimer.startPeriodic(1000 + (call Random.rand16() % 500));
        sendPing();
    }

    event void neighborTimer.fired() {
        dbg(GENERAL_CHANNEL, "Neighbor discovery timer fired\n");
        post search();
    }

    task void search() {
        dbg(GENERAL_CHANNEL, "Searching for neighbors...\n");
        sendPing();
    }
    
    command void NeighborDiscovery.printNeighbors() {
        uint8_t i;
        dbg(NEIGHBOR_CHANNEL, "Discovered Neighbors (%u total):\n", neighborCount);
        for (i = 0; i < neighborCount; i++) {
            dbg(NEIGHBOR_CHANNEL, "\t Neighbor %u: Node %u\n", i, neighbors[i].id);
        }
    }

    event void AMSend.sendDone(message_t* msg, error_t err) {
        if (&packet == msg) {
            busy = FALSE;
        }
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        if (len == sizeof(pack)) {
            pack* pkt = (pack*) payload;
            uint8_t i;
            bool found = FALSE;

            if (pkt->protocol == PROTOCOL_PING) {
                // Look for existing neighbor
                for (i = 0; i < neighborCount; i++) {
                    if (neighbors[i].id == pkt->src) {
                        neighbors[i].lastSeen = call neighborTimer.getNow();
                        found = TRUE;
                        break;
                    }
                }

                // Add new neighbor if not found and there's space
                if (!found && neighborCount < 20) {
                    neighbors[neighborCount].id = pkt->src;
                    neighbors[neighborCount].lastSeen = call neighborTimer.getNow();
                    neighborCount++;
                    dbg(NEIGHBOR_CHANNEL, "Added new neighbor: %u\n", pkt->src);
                }
            }
        }
        return msg;
    }
}