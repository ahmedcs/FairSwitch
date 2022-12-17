# CAUTION
In our deployement, we have used NetFPGA 1G platform which is currently obselete, for details on the platform used see [HERE](https://netfpga.org/NetFPGA-1G.html). However, we believe the logic provided in the verliog code can be adapted easily to the newer netfpga platforms, but we do not cover or guarantee the behaviour.

# Prerequisites
To build the bitfile on the NetFPGA platform, you need to obtain [Xilinx Vivado and ISE Design Suites](https://www.xilinx.com/products/design-tools/ise-design-suite.html) and the licence for the Ethernet MAC IP core, specifically [Tri-Mode Ethernet Media Access Controller](https://www.xilinx.com/products/intellectual-property/temac.html).  

# Building steps

First, clone the project to your local drive.

```
git clone https://github.com/ahmedcs/FairSwitch.git
```
Then, the netfpga card needs to be loaded with the binary file (or bitfile) of the FairQ-based switch (i.e., FairSwitch). The verilog code for building the FairSwitch module can be implemented on the netfpga reference [Switch](https://github.com/NetFPGA/netfpga/tree/master/projects/reference_switch) design but is also applicable to the reference [Router](https://github.com/NetFPGA/netfpga/tree/master/projects/reference_router) design. 

The file of the FairSwitch module is named **fairq_main.v** which is under the **netfpga** folder. Put the file in the src folder of the src folder of the reference switch or router and then start the synthesis. After the synthesis process is complete with no errors, you would have the new bitfile, please upload it to the netfpga card before starting the experiments.

We do not cover or provide guide on the building or deployment on the NetFPGA platform. However, to help the interested parties build and upload the new bitfile, we give the links to the official guide which is available [HERE](https://github.com/NetFPGA/netfpga/wiki/Guide) and a useful tutorial which is available on the following links: [DAY1](https://www.cl.cam.ac.uk/research/srg/netos/projects/netfpga/workshop/technion-august-2015/material/slides/2015_Summer_Camp_Day_1.pdf) and [DAY2](https://www.cl.cam.ac.uk/research/srg/netos/projects/netfpga/workshop/technion-august-2015/material/slides/2015_Summer_Camp_Day_2.pdf).

<!--
# OpenvSwitch version

You need to apply the patch that comes along with the source files to the "datapath" subfolder of the OpenvSwitch source directory. Notice that, the patch is customized to openvswitch version 2.4.0 and it may/may not work for other versions. If you are applying the patch to a different version, please read the patch file and update manually (few locations is updated).

The patch updates these files: (actions.c, datapath.c, datapath.h, Makefile.in, Module.mk)

Then you need to issue the patch command to patch (actions.c datapath.c, datapath.h, Makefile.in, Module.mk):

```
cd openvswitch-2.4.0/datapath
patch -p1 < hscc.patch
```

Copy the source and header files to the datapath folder (hscc.c and hscc.h), then we need to build and install the new openvswitch:

```
cd openvswtich-2.4.0
./configure --with-linux="/lib/modules/`uname -r`/build"
cd datapath
make clean
make
cd linux
sudo make modules_install
```

If the kernel module was not installed properly, it can be copied as follows (depending on the current location of the running OpenvSwitch):
```
cd openvswtich-2.4.0/datapath/linux
sudo cp openvswitch.ko /lib/modules/`uname -r`/kernel/net/openvswitch/openvswitch.ko
```

The location of the OpenvSwitch module can be found by the following:
```
modinfo openvswitch
```
-->

# Window Scale Module
If the source file has been changed, you need to update the name of the object file to match the new source file containing the module init_module and exit_module macros and the definition functions. SEE Makefile for more information.

Notice, you can include other source and header files but under the condition that there are a single source file containing the necessary init_module and exit_module macros and their function.


Now the output files is as follows:
```
cd endhost-wndscale
make
```
The files generated would be wnd_scale.o and wnd_scale.ko, where one ending with .o is the object file while the one ending in .ko is the module file

# Run
To install the module into the kernel
```
sudo insmode wnd_scale.ko
```

# Stop

To stop the loss_probe module and free the resources issue the following command:

```
sudo rmmod -f wnd_scale;
```

<!--
# SDN Controller Application

The simple layer 2 switch SDN controller has been adopted for implementing the HSCC SDN controller application.  
Another way to implement this is via leveraging the rich northbound API to sperate HSCC application from the real controller implementation (On-Going).

The Ryu Controller can be started on the Controller PC (which has to be connected to the switches under control) as follows:
```
cp HSCC/Controller-App/hscc_app.py ~/ryu/ryu/app/
cd ~/ryu
./bin/ryu-manager --verbose ryu/app/hscc_app.py
```

Now you need to ensure the switch is configured to connect to the controller and use the latest (preferably) openflow as follow:  
For example if the controller is located at 192.168.1.1 and want to use OF1.3
```
sudo ovs-vsctl set-controller ovsbr0 tcp:192.168.1.1:6633
sudo ovs-vsctl set bridge ovsbr0 protocols=OpenFlow13
```

Check out the configuration of the switch as follows:
```
sudo ovs-vsctl show
```

# For Tutorials on OvS and Ryu
Please check the following websites for more documentation and tutorials:  
```
https://osrg.github.io/ryu/
http://openvswitch.org
http://networkstatic.net/openflow-openvswitch-lab/
http://sdnhub.org/tutorials/ryu/
```
-->
