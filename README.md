# ViPE example

This is a quick tutorial about how to run
[ViPE](https://github.com/nv-tlabs/vipe) in a remote container environment, and
import the result into COLMAP.

## Preparation

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
   2. (Optional) Create a network volume in a region that has sufficient
      availability of GPUs, with a size of at least 10 GB. If unsure, `eu-ro-1`
      is a reasonable choice.
   3. Start a deployment using
      [this template](https://console.runpod.io/hub/template/45lmv1hk70), or
      configure the image to use `docker.io/sruggier/runpod-vipe:main`. This
      contains the ViPE source tree at `/vipe`, with a pre-built Python
      environment available at `/vipe/.env` and included in PATH.
   4. (Optional) Select the newly created network volume.
   5. Depending on the dataset involved, a minimum amount of system memory may
      be required. For a dataset involving 125 images with 12 MP resolution, 55
      GB of memory is a reasonable minimum, depending on the particular pipeline
      preset used.
   6. For a dataset of similar size, pick a GPU with at least 20 GB of VRAM if
      running with the `no_vda` preset, 24 GB for `default`, and 48 GB if using
      `dav3`.
   7. Before deploying, ensure the `SSH Access` option is selected, if shown, or
      open the overrides page for the template and manually set the `PUBLIC_KEY`
      variable to include your public key.

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

## Running ViPE

1. Open an SSH session within the pod's container:

   ```bash
   ssh vipe-pod
   ```

2. Ensure a directory exists for pipeline output:

   ```bash
   mkdir -p /workspace/output/vipe
   ```

3. Run the pipeline (choose a preset from
   [Pipeline Presets](https://nv-tlabs.github.io/vipe/reference/configuration/#pipeline-presets)):

   ```bash
   VIPE_PRESET=default; python /vipe/run.py \
   	streams=frame_dir_stream \
   	streams.base_path=/workspace/datasets/<dataset> \
   	pipeline.output.save_artifacts=true \
   	pipeline.output.save_slam_map=true \
   	pipeline.slam.visualize=true \
   	pipeline=$VIPE_PRESET \
   	pipeline.output.path=/workspace/output/vipe/$VIPE_PRESET-$(date --iso-8601=minutes)
   ```

   To enable use of CuVSLAM during frontend initialization, add
   `pipeline.slam.sparse_tracks.name=cuvslam` to the command line.

4. Export the results in a format that can be imported into tools that expect
   output generated by COLMAP (fill in the output directory):

   ```bash
   mkdir /workspace/output/COLMAP
   VIPE_OUTPUT_DIR=/workspace/output/vipe/<output directory>; \
   	echo "Exporting dense point cloud for COLMAP" && \
   	python /vipe/scripts/vipe_to_colmap.py \
   		"$VIPE_OUTPUT_DIR" \
   		-o /workspace/output/COLMAP/"$(basename "$VIPE_OUTPUT_DIR")"_dense && \
   	echo "Exporting SLAM keypoint cloud for COLMAP" && \
   	python /vipe/scripts/vipe_to_colmap.py \
   		 --use_slam_map \
   		"$VIPE_OUTPUT_DIR" \
   		-o /workspace/output/COLMAP/"$(basename "$VIPE_OUTPUT_DIR")"_sparse
   ```

   This can also be run locally after the next step, in order to optimize the
   cost associated with running the pod, but it requires the ViPE repository to
   be cloned locally.

5. (Optional) On your local system, use `rsync` to transfer the output generated
   by ViPE:

   ```bash
   rsync -rtvP vipe-pod:/workspace/output/ ~/path/to/output
   ```

   In case this will take a long time, one can also stop the GPU pod, deploy a
   CPU-based pod with the same network volume attached, and rsync from the
   cheaper pod instead.

## Import into COLMAP

For a quick sanity check, one can take the files from `vipe_to_colmap.py`, and
import them into COLMAP:

1. [Install COLMAP](https://colmap.github.io/install.html). On Debian-based
   distributions, one can use APT:

   ```bash
   apt install colmap
   ```

2. Import a point cloud into COLMAP:
   1. Run `colmap gui`
   2. Select `File > Import model`
   3. Navigate to the directory containing output from ViPE. Navigate into one
      of the folders whose name ends with `_dense` or `_sparse`, and choose the
      directory inside that one. The chosen directory should contain two
      subdirectories: `images` and `sparse`, as a COLMAP workspace directory
      would. Inside `sparse/0`, there should be files named `points3D.txt`,
      `images.txt`, and `cameras.txt`.
