#! /usr/bin/python
from TOSSIM import *
from CommandMsg import *
import sys
import time

class TestSim:
    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()
        
        # Add channels to watch
        self.t.addChannel("GENERAL", sys.stdout)
        self.t.addChannel("NEIGHBOR", sys.stdout)
        self.t.addChannel("FLOODING", sys.stdout)
        
        self.topoFile = "topo/example.topo"
        self.noiseFile = "noise/no_noise.txt"
        
    def loadTopo(self, topoFile):
        print >> sys.stderr, "Loading topology from:", topoFile
        self.topoFile = topoFile
        try:
            # Read topology from file
            with open(topoFile, "r") as f:
                self.nodes = 0
                first_line = True
                for line in f:
                    s = line.split()
                    if len(s) > 0:
                        if first_line:
                            # First line contains number of nodes
                            self.nodes = int(s[0])
                            first_line = False
                        else:
                            # Other lines contain links: source destination gain
                            if len(s) >= 3:
                                src = int(s[0])
                                dest = int(s[1])
                                gain = float(s[2])
                                self.r.add(src, dest, gain)
        except IOError as e:
            print >> sys.stderr, "Error loading topology file:", e
            sys.exit(1)
        except ValueError as e:
            print >> sys.stderr, "Error parsing topology file:", e
            sys.exit(1)
        print >> sys.stderr, "Loaded topology with", self.nodes, "nodes"

    def loadNoise(self, noiseFile):
        print >> sys.stderr, "Loading noise model from:", noiseFile
        try:
            with open(noiseFile, "r") as noise:
                for line in noise:
                    str1 = line.strip()
                    if str1:
                        val = int(str1)
                        for i in range(self.nodes):
                            self.t.getNode(i).addNoiseTraceReading(val)
            
            for i in range(self.nodes):
                print >> sys.stderr, "Creating noise model for node:", i
                self.t.getNode(i).createNoiseModel()
                self.t.getNode(i).bootAtTime((31 + self.t.ticksPerSecond() / 10) * i + 1)
        except IOError as e:
            print >> sys.stderr, "Error loading noise file:", e
            sys.exit(1)
        except ValueError as e:
            print >> sys.stderr, "Error parsing noise file:", e
            sys.exit(1)

    def bootNodes(self):
        print >> sys.stderr, "Booting nodes..."
        # Run enough events for nodes to boot
        bootTime = self.t.time() + 5 * self.t.ticksPerSecond()
        while self.t.time() < bootTime:
            self.t.runNextEvent()

    def runNeighborDiscovery(self):
        print >> sys.stderr, "Testing neighbor discovery..."
        # Let neighbor discovery work for a while
        endTime = self.t.time() + 20 * self.t.ticksPerSecond()
        while self.t.time() < endTime:
            self.t.runNextEvent()
        
        # Request neighbor lists
        for i in range(self.nodes):
            msg = CommandMsg()
            msg.set_dest(i)
            msg.set_id(2)  # Command ID for print neighbors
            msg.setElement_payload(0, 0)  # Set first payload element to 0
            
            pkt = self.t.newPacket()
            pkt.setData(msg.data)
            pkt.setType(msg.get_amType())
            pkt.setDestination(i)
            
            print >> sys.stderr, "Requesting neighbors from node", i
            pkt.deliver(i, self.t.time() + 3)
            for j in range(10):
                self.t.runNextEvent()

    def runFlooding(self):
        print >> sys.stderr, "Testing flooding..."
        # Start flood from node 0
        msg = CommandMsg()
        msg.set_dest(0)
        msg.set_id(3)  # Command ID for start flood
        msg.setElement_payload(0, 0)  # Set first payload element to 0
        
        pkt = self.t.newPacket()
        pkt.setData(msg.data)
        pkt.setType(msg.get_amType())
        pkt.setDestination(0)
        
        print >> sys.stderr, "Starting flood from node 0"
        pkt.deliver(0, self.t.time() + 5)
        
        # Let flood propagate
        endTime = self.t.time() + 10 * self.t.ticksPerSecond()
        while self.t.time() < endTime:
            self.t.runNextEvent()

def main():
    print >> sys.stderr, "Starting tests..."
    s = TestSim()
    
    # Test with different topologies
    topos = ["topo/example.topo", "topo/long_line.topo", "topo/topo.txt"]
    
    for topo in topos:
        print >> sys.stderr, "\n\nTesting with topology:", topo
        s.loadTopo(topo)
        s.loadNoise(s.noiseFile)
        s.bootNodes()
        print >> sys.stderr, "\n--- Starting Neighbor Discovery Test ---"
        s.runNeighborDiscovery()
        print >> sys.stderr, "\n--- Starting Flooding Test ---"
        s.runFlooding()
        print >> sys.stderr, "Completed tests for topology:", topo
        print >> sys.stderr, "-" * 50

    print >> sys.stderr, "\nAll tests finished!"

if __name__ == '__main__':
    main()