//
//  remount.m
//  Elysian
//
//  Created by chris  on 4/1/20.
//  Copyright © 2020 chr1s_0x1. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/mount.h>
#include <sys/stat.h>
#include "IOKit/IOKit.h"
#import <sys/snapshot.h>
#import "utils.h"
#import "remount.h"
#import "jelbrekLib.h"
#import "kernel_memory.h"
#include "offsets.h"

char name[20];

bool renameSnapRequired() {
    int fd = open("/", O_RDONLY, 0);
    int count = list_snapshots("/");
    close(fd);
    
    return count == -1 ? YES : NO;
}

int MountFS(uint64_t vnode) {
    // find disk0s1s1
    uint64_t devmount = rk64(vnode + 0xd8);
    uint64_t devvp = rk64(devmount + 0x980);
    uint64_t devname = rk64(devvp + 0xb8);

    kread(devname, name, 20);
    
    LOGM("Got dev vnode: %s\n", name);
    
    // get dev flags
     uint64_t spec = rk64(devvp + 0x78); // 0x78 = specinfo
     uint32_t specflags = rk32(spec + 0x10); // 0x10 = specinfo flags
    LOGM("Found dev flags: %u\n", specflags);
    
    // setting spec flags to 0
    wk32(spec + 0x10, 0);
    
    // create dir for mount
    mkdir("/var/rootmnt", 0755);
    chown("/var/rootmnt", 0, 0);
    char *path = "/var/rootmnt";
    
    // setup mount args
    char *fspec = "/dev/disk0s1s1";
    struct hfs_mount_args mntargs = {};
    mntargs.fspec = fspec;
    mntargs.hfs_mask = 1;
    gettimeofday(NULL, &mntargs.hfs_timezone);
    
    // Now for actual mounting of rootFS
    kern_return_t retval = mount("apfs", path, 0, &mntargs);
    if(retval != KERN_SUCCESS) {
        return _MOUNTFAILED;
    }
    
    return _MOUNTSUCCESS;
}

// Credit to Chimera13
  
int remountFS() {
    LOG("Remounting RootFS..\n");
    // check if we can open "/"
    int file = open("/", O_RDONLY, 0);
    if(file <= 0) {
        LOG("ERR: Failed to open /, are we root?\n");
        return 1;
    }
    
    // get our and kernels proccess
    uint64_t kernel_proc = proc_of_pid(0);
    LOGM("Got kernel proccess: 0x%llx\n", kernel_proc);
    uint64_t our_proc = find_self_task();
    LOGM("Got our task: 0x%llx\n", our_proc);
    
    // Find launchd
    uint64_t launchd_proc = proc_of_pid(1);
    if(launchd_proc == 0) {
        LOG("ERR: Couldn't find launchd process\n");
        return _NOLAUNCHDERR;
    }
    LOGM("Found launchd: 0x%llx\n", launchd_proc);
    
    // find vnode
    uint64_t textvp = rk64(launchd_proc + 0x238); // 0x238 = textvp
    uint64_t vname = rk64(textvp + 0xb8); // 0xb8 = vnode name

    kread(vname, name, 20);
    
    LOGM("Got vnode: %s\n", name);
    
    // find rootvnode
    uint64_t sbin = rk64(textvp + 0xc0); // 0xc0 = vnode parent
    uint64_t rootvnode = rk64(sbin + 0xc0);
    uint64_t rootname = rk64(rootvnode + 0xb8);
    kread(rootname, name, 20);
    
    LOGM("Got vnode (should be root): %s\n", name);
    
    // find vnode flags
    uint64_t vnodeflags = rk32(rootvnode + 0x54); // 0x54 = flags
    LOGM("vnode flags: 0x%llx\n", vnodeflags);
    
    bool required = renameSnapRequired();
    if(required == NO) {
        LOG("Snapshot already renamed!\n");
        goto next_step;
    }
    
    // Gonna need kernel perms for this
    uint64_t kern_ucred = rk64(kernel_proc + 0x100);
    uint64_t our_creds = rk64(our_proc + 0x100);
    wk64(our_proc + 0x100, kern_ucred);
    
    // Mount FS
    int mount = MountFS(rootvnode);
    if(mount != _MOUNTSUCCESS){
        LOG("ERR: Failed to mount FS\n");
        return _MOUNTFAILED;
    }
    LOG("Succesfully mounted FS\n");
    
    /*                                      will uncomment this later
    int snaps = list_snapshots("/");
    if(snaps < 0) {
        LOG("Failed to find snapshots\n");
        return _NOSNAPS;
    }
    LOG("Found System snapshot(s)\n");
    */
    
    wk64(our_proc + 0x100, our_creds);
    
next_step:
    return 0;
}