# ViPE example

This is a quick tutorial about how to run
[ViPE](https://github.com/nv-tlabs/vipe) in a remote container environment, and
import the result into COLMAP.

## Steps

1. Download the dataset to use. In this case, a folder full of images is
   assumed.

2. Install the rerun viewer, using
   [one of the available alternatives](https://rerun.io/docs/getting-started/install-rerun/viewer).
   This is optional, but very useful for troubleshooting tracking failures. If
   you have `uv` installed, you can also use it like so:

   ```bash
   uv tool install rerun-sdk
   ```

3. (Optional) To minimize costs, one can set up a networked volume in Runpod and
   sync files in advance of starting a pod using the
   [S3-compatible API](https://docs.runpod.io/storage/s3-api). However, the API
   has fairly narrow compatibility, and may require use of specific tools, and
   versions of those tools. For small-scale use, it may not be worth the process
   of trial and error needed to find a working combination, and can be skipped
   in favour of using `rsync`, as documented below.

4. Follow the existing instructions to
   [Generate an SSH key and add it to your Runpod account](https://docs.runpod.io/pods/configuration/use-ssh#generate-an-ssh-key-and-add-it-to-your-runpod-account).

5. Provision a container environment (e.g. from Runpod). For this example, I
   used the following settings:
   1. In the Runpod console, go to
      [Early access features](https://console.runpod.io/user/early-access) and
      enable the `New Pod deploy page` option.
   2. Create a 50 GB network volume in a region that has sufficient availability
      of GPUs. If unsure, `eu-ro-1` is a reasonable choice.
   3. Either create a new template, or enter the options below in the pod
      deployment page.
   4. Select the `runpod/pytorch:1.1.0-cu1281-torch291-ubuntu2404` image (or
      equivalent), to match CUDA versions with what ViPE has in its
      [`uv.lock`](https://github.com/nv-tlabs/vipe/blob/95a8816947602ddc26fcb7a80bea4f9313059578/uv.lock)
      file.
   5. Select the newly created network volume.
   6. Depending on the dataset involved, a minimum amount of system memory may
      be required. For a dataset involving 125 images with 12 MP resolution, 55
      GB of memory is a reasonable minimum, depending on the particular pipeline
      preset used.
   7. For a dataset of similar size, pick a GPU with at least 20 GB of VRAM if
      running with the `no_vda` preset, 24 GB for `default`, and 48 GB if using
      `dav3`.
   8. Before deploying, ensure the `SSH Access` option is selected.

6. While waiting for the pod, start the rerun viewer locally, in order to
   receive log data from ViPE through connections forwarded by SSH from a remote
   port, which will be configured below:

   ```bash
   rerun
   ```

7. Once the container comes up, update your SSH configuration with an alias for
   the environment. This is optional, but greatly simplifies things like `rsync`
   command lines:

   1. Make an include directory for your SSH configuration:

      ```bash
      mkdir ~/.ssh/config.d
      ```

   1. Add an `Include` directive to `~/.ssh/config` for the new directory:

      ```ssh_config
      Include ~/.ssh/config.d/*.conf
      ```

   1. Create a file at `~/.ssh/config.d/runpod.conf` with the following
      contents, filling in the IP address and port from the `Connect` tab for
      your pod in the Runpod console:

      ```ssh_config
      Host vipe-pod
      	User root
      	# These will need to be updated after making any changes to the container.
      	Hostname <IP address>
      	Port <port>
      	# This will generate benign errors on multiple connections, but ensures
      	# rerun information is forwarded to the local system instead of trying to
      	# spawn a viewer within the container.
      	RemoteForward 9876 localhost:9876
      ```

8. Use `rsync` to copy the directory full of images over to the remote
   container:

   ```bash
   rsync -rtvP --mkpath path/to/dataset vipe-pod:/workspace/datasets
   ```

9. Open an SSH session within the pod's container:

   ```bash
   ssh vipe-pod
   ```

10. Clone the ViPE repository:

    ```bash
    git clone https://github.com/sruggier/vipe.git /workspace/vipe
    ```

    or, use an existing clone of upstream, but with the same fixes applied:

    ```bash
    git clone https://github.com/nv-tlabs/vipe.git /workspace/vipe
    cd /workspace/vipe
    git remote add sruggier https://github.com/sruggier/vipe.git
    git fetch sruggier
    git checkout -b sruggier-main -t sruggier/main
    ```

11. Create a Python environment with all of the needed software installed:

    ```bash
    uv sync --link-mode=symlink
    ```

    During the first run, this will take a long time, roughly 105 minutes, due
    to the very slow network storage volume, but the downloaded and built
    packages will be cached, and later executions will generally take much less
    time to execute.

    In practice, one would want to either execute pods using a custom container
    image that contains the result of this build step, or perform the build on
    the container's own storage, which is faster. To do that:
    1. allocate at least 15 GB of space on the container storage
    2. use a symlink to redirect `/workspace/.cache/uv` to a directory under
       `/tmp`
    3. Perform the build, as above
    4. Replace the symlink with the real cache directory produced by running the
       build.

12. (Optional) To enable use of the `lyra` preset, install MoGe:

    ```bash
    uv pip install --link-mode=symlink 'git+https://github.com/microsoft/MoGe.git'
    ```

13. (Optional) To test sparse tracking, install PyCuVSLAM:

    ```bash
    wget https://github.com/nvidia-isaac/cuVSLAM/releases/download/v17.0.0/cuvslam-17.0.0+cu12-cp310-cp310-manylinux_2_35_x86_64.whl
    uv pip install --link-mode=symlink ./cuvslam-17.0.0+cu12-cp310-cp310-manylinux_2_35_x86_64.whl
    ```

14. Ensure a directory exists for pipeline output:

    ```bash
    mkdir /workspace/vipe-output
    ```

15. Run the pipeline (choose a preset from
    [Pipeline Presets](https://nv-tlabs.github.io/vipe/reference/configuration/#pipeline-presets)):

    ```bash
    VIPE_PRESET=default; uv run \
    	--link-mode=symlink \
    	--directory /workspace/vipe \
    	python run.py \
    	streams=frame_dir_stream \
    	streams.base_path=/workspace/datasets/<dataset> \
    	pipeline.output.save_artifacts=true \
    	pipeline.output.save_slam_map=true \
    	pipeline.slam.visualize=true \
    	pipeline=$VIPE_PRESET \
    	pipeline.output.path=/workspace/vipe-output/$VIPE_PRESET-$(date --iso-8601=minutes)
    ```

    To enable use of CuVSLAM during frontend initialization, add
    `pipeline.slam.sparse_tracks.name=cuvslam` to the command line.

16. Export the results in a format that can be imported into COLMAP (fill in the
    output directory):

    ```bash
    VIPE_OUTPUT_DIR=/workspace/vipe-output/<output directory>
    echo "Exporting dense point cloud for COLMAP"
    uv run --directory /workspace/vipe --link-mode=symlink python \
    	scripts/vipe_to_colmap.py "$VIPE_OUTPUT_DIR"
    echo "Exporting SLAM keypoint cloud for COLMAP"
    uv run --directory /workspace/vipe --link-mode=symlink python \
    	scripts/vipe_to_colmap.py "$VIPE_OUTPUT_DIR" \
    	-o "$dir"_colmap-slam-keypoints --use_slam_map
    ```

    This can also be run locally after the next step, in order to optimize the
    cost associated with running the pod, but it requires the ViPE repository to
    be cloned locally.

17. On your local system, use `rsync` to transfer the output generated by ViPE:

    ```bash
    rsync -rtvP vipe-pod:/workspace/vipe-output/ ~/path/to/vipe-output
    ```

    In case this will take a long time, one can also stop the GPU pod, deploy a
    CPU-based pod with the same network volume attached, and rsync from the
    cheaper pod instead.

18. [Install COLMAP](https://colmap.github.io/install.html). On Debian-based
    distributions, one can use APT:

    ```bash
    apt install colmap
    ```

    Version 3.10 should work, but newer versions may raise an exception during
    import, because of the shortcomings described in
    [nv-tlabs/vipe#65](https://github.com/nv-tlabs/vipe/issues/65).

19. Import a point cloud into COLMAP:
    1. Run `colmap gui`
    2. Select `File > Import model`
    3. Navigate to the directory containing output from ViPE. Navigate into one
       of the folders whose name ends with `_colmap`, or
       `_colmap-slam-keypoints`, and choose the directory inside that one. The
       chosen directory should contain a folder named `images`, and files named
       `points3D.txt`, `images.txt`, and `cameras.txt`.
