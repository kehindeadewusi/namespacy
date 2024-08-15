#!/bin/bash

# This script is called by the `ci/run_conditionals.sh` script.
# A specific `TEST_TYPE` passed down from a GitHub Actions workflow will be run. 
# Depending on the value of 
# `TEST_TYPE`. For example, if `TEST_TYPE` is
# `test`, the `hatch run cov` session will be run.

# This script requires the following environment variables to be set:
# `TEST_TYPE` should be one of ["typecheck", "lint", "test", "publish-feature", "publish-prod"]

set -e

if [ -z "${TEST_TYPE}" ]; then
    echo "missing TEST_TYPE env var"
    exit 1
fi

# Don't fail on errors so we can capture all of the output
set +e

case ${TEST_TYPE} in
    typecheck)
        mypy . --no-namespace-packages --install-types --non-interactive --cache-dir .
        
        retval=$?
        rm -rf **/.mypy_cache
        ;;
    lint)
        ruff check .

        retval=$?

        rm -rf **/.ruff_cache
        ;;
    test)
        hatch run cov

        # This line needs to be directly after `nox -s docs` in order
        # for the failure to appear in Github presubmits
        retval=$?

        # Clean up built docs and python cache after the build process to avoid
        # `[Errno 28] No space left on device`
        # See https://github.com/googleapis/google-cloud-python/issues/12271
        rm -rf **/_build
        ;;
    publish-feature)
        python -m build # build python wheel package

        timestamp=$(date +'%Y%m%d%H%M%S')
        BUILD_TAG=${timestamp}_${TARGET_ENV}
        WHEEL=$(ls dist/*.whl)
        FINAL_WHEEL=$(echo $WHEEL | sed "s/-py3-none-any\.whl/-${BUILD_TAG}-py3-none-any\.whl/")
        mv $WHEEL $FINAL_WHEEL

        databricks fs cp "$FINAL_WHEEL" dbfs:/flow_temp/

        echo "$FINAL_WHEEL"
        echo "copied to Databricks dbfs:/flow_temp"

        retval=$?
 
        rm -rf **/_build
        ;;
    publish-prod)
        python -m build

        WHEEL=$(ls dist/*.whl)
        databricks fs cp "$WHEEL_FILE" dbfs:/flow_temp/

        echo "$WHEEL"
        echo "copied to Databricks dbfs:/flow_temp"

        # make release
        VERSION=`hatch version`
        gh release create $VERSION --target main --generate-notes

        retval=$?       
        ;;
esac

# Clean up `__pycache__` and `.nox` directories to avoid error
# `No space left on device` seen when running tests in Github Actions
find . | grep -E "(__pycache__)" | xargs rm -rf
#rm -rf .nox

exit ${retval}
