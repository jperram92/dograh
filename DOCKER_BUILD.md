# Docker Build Instructions

## Pipecat Submodule Integration

The Dograh project uses pipecat as a git submodule. The Docker build process automatically synchronizes the pipecat version between the submodule and the Docker image.

### How It Works

1. **Automatic Version Sync**: The Dockerfile accepts `PIPECAT_COMMIT` as a build argument
2. **CI/CD**: GitHub Actions automatically extract the submodule commit and pass it during build
3. **Local Development**: Use the provided scripts or set the environment variable

### Building Locally

#### Option 1: Using the Helper Script (Recommended)
```bash
# From the dograh directory
./scripts/docker-build-local.sh
```

This script automatically:
- Extracts the pipecat commit from the submodule
- Sets the PIPECAT_COMMIT environment variable
- Runs docker-compose build with the correct version

#### Option 2: Manual Build with docker-compose
```bash
# From the dograh directory
export PIPECAT_COMMIT=$(./scripts/get_pipecat_commit.sh)
docker-compose build
```

#### Option 3: Direct Docker Build
```bash
# From the dograh directory
PIPECAT_COMMIT=$(./scripts/get_pipecat_commit.sh)
docker build --build-arg PIPECAT_COMMIT=$PIPECAT_COMMIT -f api/Dockerfile ./api
```

### Updating Pipecat

When you update the pipecat submodule:

1. Update the submodule to the desired commit:
   ```bash
   cd pipecat
   git checkout <desired-commit>
   cd ..
   git add pipecat
   git commit -m "Update pipecat submodule"
   ```

2. **No Dockerfile changes needed!** The build process automatically uses the new commit.

3. Push your changes - the CI/CD pipeline will automatically build with the correct version.

### Troubleshooting

If you encounter build errors related to PIPECAT_COMMIT:

1. Ensure the pipecat submodule is initialized:
   ```bash
   git submodule update --init --recursive
   ```

2. Verify the submodule has a valid commit:
   ```bash
   ./scripts/get_pipecat_commit.sh
   ```

3. For local builds, ensure you're using one of the methods above that sets PIPECAT_COMMIT.

### Benefits

- ✅ No manual Dockerfile updates when pipecat is updated
- ✅ Guaranteed synchronization between submodule and Docker image
- ✅ Eliminates version mismatch errors
- ✅ Simpler workflow for developers