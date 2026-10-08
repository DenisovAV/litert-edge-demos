# An Android phone as a Wi-Fi camera for the Live camera demo

On a Raspberry Pi 5 or a Jetson (or any Linux PC) the live camera demo can use an Android phone's camera over
Wi-Fi. The phone streams video; the board does all the AI.

**Both devices must be on the same Wi-Fi network** (or the board on Ethernet in the same network). Guest networks
that isolate devices do not work: use your own router or the phone's hotspot (connect the board to the phone's
hotspot, then the phone's address is usually `192.168.43.1` or shown in the hotspot settings).

## Recommended: IP Webcam + the app's Network camera

1. **On the phone:** install **IP Webcam** (by Pavel Khlebovich, free on Google Play).
2. Open it. Optional, under **Video preferences**: *Video resolution* 1280×720 or 640×480 (the detector works at
   640 pixels anyway; smaller is smoother); *Prevent phone sleep* on.
3. Scroll to the bottom and tap **Start server**. The screen shows the address, for example
   `http://192.168.1.23:8080`.
4. **On the board:** open **Live camera**, choose **Network camera (URL)** as the camera source and enter the
   address **with `/video` at the end**: `http://192.168.1.23:8080/video`. Connect.
5. Boxes appear on the live picture; ask questions as usual. The source and its frame rate are shown in the demo.

Check in a browser first if it does not connect: `http://192.168.1.23:8080` on the board should show IP Webcam's
page. If it does not, the two devices cannot see each other on the network (see above).

Tips: put the phone on a stand; plug it into a charger (streaming drains the battery); the back camera is the
default (switch in IP Webcam's settings); expect about 0.1–0.3 s of delay.

The board decodes the phone's JPEG frames with **libturbojpeg**, which the Linux bundle ships. If the live picture
says **"slow JPEG decoder"** (and `./run.sh` warned about `libturbojpeg.so.0`), the bundle was built without it:
install it on the board and restart the app:
```sh
sudo apt install libturbojpeg      # Ubuntu, Jetson (JetPack 6)
sudo apt install libturbojpeg0     # Raspberry Pi OS, Debian
```
Without it the detector sees only a few frames per second.

## Fallback: the phone as a regular webcam (v4l2loopback)

If the in-app network camera cannot be used, turn the same stream into a virtual webcam that every Linux app sees.
Tested on Ubuntu 22.04 arm64 (kernel 6.8) with the stream of an IP-Webcam-compatible server.

1. Install the tools and load the module:
   ```sh
   sudo apt install -y v4l2loopback-dkms ffmpeg v4l-utils
   sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="Phone" exclusive_caps=1
   ```
   If the package fails to build (`dpkg returned an error code`, as with Ubuntu 22.04's 0.12.7 on kernel 6.8 or
   newer), build the module from source instead:
   ```sh
   sudo apt remove -y v4l2loopback-dkms
   sudo apt install -y build-essential git linux-headers-$(uname -r)    # Raspberry Pi OS: raspberrypi-kernel-headers
   git clone --depth 1 https://github.com/umlaeute/v4l2loopback.git
   cd v4l2loopback && make && sudo make install && sudo depmod -a
   sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="Phone" exclusive_caps=1
   ```
   If `modprobe` says *Unknown symbol in module*, the kernel's video core module is missing (cloud and minimal
   kernels): `sudo apt install linux-modules-extra-$(uname -r)` and run `modprobe` again.
2. Feed it the phone's stream and keep this running:
   ```sh
   ffmpeg -i http://192.168.1.23:8080/video -vf format=yuv420p -f v4l2 /dev/video10
   ```
3. Check it: `v4l2-ctl --list-devices` shows **Phone** with `/dev/video10`. In the app choose the device camera
   **Phone**.
4. If the app or `ffmpeg` says *Permission denied* on `/dev/video10`: `sudo usermod -aG video $USER`, then log out
   and back in.

- On a Jetson (JetPack 6, kernel 5.15) the packaged module normally builds; it needs `nvidia-l4t-kernel-headers`.
  If it does not, use the recommended way above.
