#include <Timer.h>
#include "../../includes/am_types.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/NeighborDiscoveryDefs.h"

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

   neighbor_entry_t neighbors[MAX_NEIGHBORS];
   uint8_t neighborCount = 0;
   uint8_t discoveryPeriod = 0;  // Track discovery periods for aging
   message_t packet;
   bool busy = FALSE;

   void sendPing() {
       if (!busy) {
           pack* msg = (pack*)(call Packet.getPayload(&packet, sizeof(pack)));
           if (msg == NULL) return;

           msg->src = TOS_NODE_ID;
           msg->dest = AM_BROADCAST_ADDR;
           msg->seq = discoveryPeriod;  // Use discovery period as sequence
           msg->TTL = 1;
           msg->protocol = PROTOCOL_PING;

           if (call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(pack)) == SUCCESS) {
               busy = TRUE;
               dbg(NEIGHBOR_CHANNEL, "Sent neighbor discovery ping (period %u)\n", discoveryPeriod);
           }
       }
   }

   // Optimized neighbor lookup using linear search with early exit
   int8_t findNeighbor(uint16_t nodeId) {
       uint8_t i;
       for (i = 0; i < neighborCount; i++) {
           if (neighbors[i].id == nodeId) {
               return i;
           }
       }
       return -1;
   }

   // Remove stale neighbors and age existing ones
   void cleanupNeighbors() {
       uint8_t i = 0;
       uint8_t writeIndex = 0;

       for (i = 0; i < neighborCount; i++) {
           neighbors[i].age++;
           if (neighbors[i].age < NEIGHBOR_TIMEOUT) {
               // Keep this neighbor, possibly at a different position
               if (writeIndex != i) {
                   neighbors[writeIndex] = neighbors[i];
               }
               writeIndex++;
           } else {
               dbg(NEIGHBOR_CHANNEL, "Removed stale neighbor: %u\n", neighbors[i].id);
           }
       }
       neighborCount = writeIndex;
   }

    command void NeighborDiscovery.start() {
        // Start the neighbor discovery process with randomized timing
        uint16_t jitter = call Random.rand16() % DISCOVERY_JITTER;
        call neighborTimer.startPeriodic(DISCOVERY_INTERVAL + jitter);
        sendPing();
        dbg(NEIGHBOR_CHANNEL, "Neighbor discovery started with interval %u ms\n", DISCOVERY_INTERVAL + jitter);
    }

    event void neighborTimer.fired() {
        discoveryPeriod++;
        cleanupNeighbors();  // Clean up stale neighbors each period
        post search();
    }

    task void search() {
        dbg(NEIGHBOR_CHANNEL, "Searching for neighbors...\n");
        sendPing();
    }
    
    command void NeighborDiscovery.printNeighbors() {
        uint8_t i;
        dbg(GENERAL_CHANNEL, "Discovered Neighbors (%u total):\n", neighborCount);
        for (i = 0; i < neighborCount; i++) {
            dbg(GENERAL_CHANNEL, "\t Neighbor %u: Node %u\n", i, neighbors[i].id);
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
            int8_t neighborIndex;

            if (pkt->protocol == PROTOCOL_PING && pkt->src != TOS_NODE_ID) {
                neighborIndex = findNeighbor(pkt->src);

                if (neighborIndex >= 0) {
                    // Update existing neighbor
                    neighbors[neighborIndex].age = 0;  // Reset age
                    dbg(NEIGHBOR_CHANNEL, "Updated existing neighbor: %u\n", pkt->src);
                } else if (neighborCount < MAX_NEIGHBORS) {
                    // Add new neighbor
                    neighbors[neighborCount].id = pkt->src;
                    neighbors[neighborCount].age = 0;
                    neighborCount++;
                    dbg(NEIGHBOR_CHANNEL, "Added new neighbor: %u (total: %u)\n", pkt->src, neighborCount);
                } else {
                    dbg(NEIGHBOR_CHANNEL, "Neighbor table full, ignoring new neighbor: %u\n", pkt->src);
                }
            }
        }
        return msg;
    }
}