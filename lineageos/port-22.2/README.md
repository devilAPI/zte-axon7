# LineageOS 22.2 port work

`device_zte_axon7/`: the device tree forward-port as a patch series on top
of blueyfish/android_device_zte_axon7 `lineage-18.1` (commit ccdff3a).
Status and next steps: `PORTING-22.2.md` in the tree (added by the last patch).

Apply:

```sh
git clone -b lineage-18.1 https://github.com/blueyfish/android_device_zte_axon7
cd android_device_zte_axon7 && git checkout ccdff3a && git switch -c lineage-22.2
git am /path/to/lineageos/port-22.2/device_zte_axon7/*.patch
```

On the build server it is branch `lineage-22.2` of
`/srv/port/android_device_zte_axon7`. After `repo sync`, use it in the tree:

```sh
cd /srv/aosp/lineage-22.2/device/zte/axon7
git fetch /srv/port/android_device_zte_axon7 lineage-22.2 && git checkout FETCH_HEAD
```
