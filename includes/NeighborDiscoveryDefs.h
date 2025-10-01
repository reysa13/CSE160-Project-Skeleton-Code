#ifndef __NEIGHBOR_DISCOVERY_DEFS_H__
#define __NEIGHBOR_DISCOVERY_DEFS_H__

// Neighbor Discovery Configuration Constants
#define MAX_NEIGHBORS 20                // Maximum number of neighbors to track
#define NEIGHBOR_TIMEOUT 5              // Discovery periods before removing stale neighbors  
#define DISCOVERY_INTERVAL 1000         // Base discovery interval in milliseconds
#define DISCOVERY_JITTER 500           // Random jitter range in milliseconds

// Neighbor Entry Data Structure
typedef nx_struct neighbor_entry {
    nx_uint16_t id;                    // Node ID of the neighbor
    nx_uint8_t age;                    // Number of discovery periods since last contact
} neighbor_entry_t;

#endif // __NEIGHBOR_DISCOVERY_DEFS_H__