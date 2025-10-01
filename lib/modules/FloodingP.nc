#include <Timer.h>
#include "../../includes/packet.h"
#include "../../includes/channels.h"

module FloodingP {
   provides interface Flooding;

   uses interface Timer<TMilli> as floodTimer;
   uses interface AMSend;
   uses interface Receive;
   uses interface Packet;
   uses interface AMPacket;
   uses interface Random;
}

implementation {
    // Task declaration must come before usage
    task void flood();

    #define MAX_SEQUENCE_CACHE 10
    #define FLOOD_TTL 15  // More reasonable TTL for typical network sizes
    #define FLOOD_DELAY_BASE 100  // Base delay in ms
    #define FLOOD_DELAY_JITTER 400  // Random jitter range

    typedef struct {
        uint16_t src;
        uint16_t seq;
    } seq_cache_entry_t;

    seq_cache_entry_t seqCache[MAX_SEQUENCE_CACHE];
    uint8_t seqCacheSize = 0;
    uint8_t seqCacheIndex = 0;  // For circular buffer

    message_t packet;
    bool busy = FALSE;
    uint16_t seqNo = 0;

    // Check if we've already seen this sequence number from this source
    bool isDuplicate(uint16_t src, uint16_t seq) {
        uint8_t i;
        for (i = 0; i < seqCacheSize; i++) {
            if (seqCache[i].src == src && seqCache[i].seq == seq) {
                return TRUE;
            }
        }
        return FALSE;
    }

    // Add sequence to cache (circular buffer)
    void addToSeqCache(uint16_t src, uint16_t seq) {
        seqCache[seqCacheIndex].src = src;
        seqCache[seqCacheIndex].seq = seq;
        seqCacheIndex = (seqCacheIndex + 1) % MAX_SEQUENCE_CACHE;

        if (seqCacheSize < MAX_SEQUENCE_CACHE) {
            seqCacheSize++;
        }
    }

    command void Flooding.startFlooding() {
        // Start the flooding process with random initial delay to avoid collisions
        if (!busy) {
            uint16_t delay = FLOOD_DELAY_BASE + (call Random.rand16() % FLOOD_DELAY_JITTER);
            call floodTimer.startOneShot(delay);
            dbg(FLOODING_CHANNEL, "Flooding scheduled to start in %u ms\n", delay);
        } else {
            dbg(FLOODING_CHANNEL, "Flooding already in progress\n");
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
            if (msg == NULL) {
                dbg(FLOODING_CHANNEL, "Failed to get packet payload\n");
                return;
            }

            seqNo++;  // Increment sequence number for this flood
            msg->src = TOS_NODE_ID;
            msg->dest = AM_BROADCAST_ADDR;
            msg->seq = seqNo;
            msg->TTL = FLOOD_TTL;
            msg->protocol = PROTOCOL_FLOOD;

            // Add to our own cache to prevent re-processing
            addToSeqCache(TOS_NODE_ID, seqNo);

            if (call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(pack)) == SUCCESS) {
                busy = TRUE;
                dbg(FLOODING_CHANNEL, "Flood packet sent: src=%u, seq=%u, TTL=%u\n",
                    TOS_NODE_ID, seqNo, FLOOD_TTL);
            } else {
                dbg(FLOODING_CHANNEL, "Flood packet send failed\n");
            }
        } else {
            dbg(FLOODING_CHANNEL, "Flood busy, cannot send\n");
        }
    }

    event void AMSend.sendDone(message_t* msg, error_t err) {
        if (&packet == msg) {
            busy = FALSE;
            if (err == SUCCESS) {
                dbg(FLOODING_CHANNEL, "Flood packet send completed successfully\n");
            } else {
                dbg(FLOODING_CHANNEL, "Flood packet send failed with error: %u\n", err);
            }
        }
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        if (len == sizeof(pack)) {
            pack* pkt = (pack*) payload;

            if (pkt->protocol == PROTOCOL_FLOOD && pkt->src != TOS_NODE_ID) {
                // Check if we've already seen this flood message
                if (!isDuplicate(pkt->src, pkt->seq)) {
                    // New flood message - add to cache and re-flood if TTL > 0
                    addToSeqCache(pkt->src, pkt->seq);
                    dbg(FLOODING_CHANNEL, "Received new flood: src=%u, seq=%u, TTL=%u\n",
                        pkt->src, pkt->seq, pkt->TTL);

                    if (pkt->TTL > 0 && !busy) {
                        // Decrement TTL and re-flood
                        pack* fwdMsg = (pack*)(call Packet.getPayload(&packet, sizeof(pack)));
                        if (fwdMsg != NULL) {
                            *fwdMsg = *pkt;  // Copy the packet
                            fwdMsg->TTL--;

                            if (call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(pack)) == SUCCESS) {
                                busy = TRUE;
                                dbg(FLOODING_CHANNEL, "Re-flooding packet: TTL=%u\n", fwdMsg->TTL);
                            }
                        }
                    }
                } else {
                    dbg(FLOODING_CHANNEL, "Ignoring duplicate flood: src=%u, seq=%u\n",
                        pkt->src, pkt->seq);
                }
            }
        }
        return msg;
    }
}