FROM quay.io/jupyter/datascience-notebook:r-4.3.1

###############################################################################
# Environment Variables
###############################################################################
ENV GITHUB_CLI_VERSION=2.30.0 \
    QUARTO_VERSION=1.5.57 \
    R_STUDIO_VERSION=2023.12.1-402

###############################################################################
# System Installation (root)
###############################################################################
USER root

# System dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # General utilities
        lmodern \
        file \
        curl \
        g++ \
        tmux \
        # RStudio Server dependencies
        psmisc \
        lsb-release \
        libssl-dev \
        libclang-dev \
        libpq5 \
        libtiff-dev \
        && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/* /tmp/library-scripts

# R compiler settings for optimized builds
RUN R -e "dotR <- file.path(Sys.getenv('HOME'), '.R'); \
          if(!file.exists(dotR)){ dir.create(dotR) }; \
          Makevars <- file.path(dotR, 'Makevars'); \
          if (!file.exists(Makevars)){ file.create(Makevars) }; \
          cat('\nCXXFLAGS=-O3 -fPIC -Wno-unused-variable -Wno-unused-function', \
              'CXX14 = g++ -std=c++1y -fPIC', \
              'CXX = g++', \
              'CXX11 = g++', \
              file = Makevars, sep = '\n', append = TRUE)"
RUN chmod 666 ${HOME}/.R/Makevars

# Set CRAN mirror
RUN R -e "dotRprofile <- file.path(Sys.getenv('HOME'), '.Rprofile'); \
          if(!file.exists(dotRprofile)){ file.create(dotRprofile) }; \
          cat('local({r <- getOption(\"repos\")', \
              'r[\"CRAN\"] <- \"https://cloud.r-project.org\"', \
              'options(repos=r)', \
              '})', \
              file = dotRprofile, sep = '\n', append = TRUE)"
RUN chmod 666 ${HOME}/.Rprofile

# Install Quarto (publishing system for R and Python)
RUN curl --silent -L --fail \
        https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.deb > /tmp/quarto.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends /tmp/quarto.deb && \
    rm -rf /tmp/quarto.deb /var/lib/apt/lists/* /tmp/library-script && \
    apt-get clean

# Install RStudio Server
RUN wget -q https://download2.rstudio.org/server/jammy/amd64/rstudio-server-${R_STUDIO_VERSION}-amd64.deb && \
    apt-get install -yq --no-install-recommends ./rstudio*.deb && \
    rm -f ./rstudio*.deb && \
    apt-get clean && \
    chmod 777 /var/run/rstudio-server && \
    chmod +t /var/run/rstudio-server

###############################################################################
# User Installation
###############################################################################
USER ${NB_USER}

# Conda/Mamba packages (Jupyter setup)
RUN mamba install -y -c conda-forge --freeze-installed \
        jupyter-server-proxy=4.1.0 \
        jupyter-rsession-proxy=2.2.0 \
        && \
    mamba clean --all

# PyPI packages
RUN pip install \
        nbgitpuller \
        jupyterlab-quarto==0.2.8 \
        radian==0.6.11 \
        && \
    jupyter labextension enable nbgitpuller

###############################################################################
# R Package Installation
###############################################################################

# Infrastructure packages (versioned for reproducibility)
RUN R -q -e 'remotes::install_version("markdown",      version="1.12",   repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("languageserver", version="0.3.16", repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("httpgd",         version="2.0.1",  repos="https://cloud.r-project.org")'

# VS Code R debugger (latest dev version)
RUN R -q -e 'remotes::install_github("ManuelHentschel/vscDebugger")'

# Project R packages (pinned versions for reproducibility)
RUN R -q -e 'remotes::install_version("cowplot",     version="1.2.0",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("data.table",  version="1.17.8", repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("demography",  version="2.0.1",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("dplyr",       version="1.1.4",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("forecast",    version="8.24.0", repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("ggnewscale",  version="0.5.2",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("ggplot2",     version="4.0.0",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("gnm",         version="1.1-5",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("gridExtra",   version="2.3",    repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("janitor",     version="2.2.1",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("lpSolve",     version="5.6.23", repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("lubridate",   version="1.9.4",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("mgcv",        version="1.9-3",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("patchwork",   version="1.3.2",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("plotly",      version="4.12.0", repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("purrr",       version="1.0.0",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("readr",       version="2.1.5",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("readxl",      version="1.4.5",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("reshape2",    version="1.4.4",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("StMoMo",      version="0.4.1",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("strucchange", version="1.5-4",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("stringr",     version="1.5.2",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("tseries",     version="0.10-58",repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("tidyverse",   version="2.0.0",  repos="https://cloud.r-project.org")'
RUN R -q -e 'remotes::install_version("Iso",         version="0.0-21", repos="https://cloud.r-project.org")'

###############################################################################
# Developer Tools
###############################################################################

# GitHub CLI (for pushing/pulling from GitHub inside the container)
RUN wget https://github.com/cli/cli/releases/download/v${GITHUB_CLI_VERSION}/gh_${GITHUB_CLI_VERSION}_linux_amd64.tar.gz -O - | \
    tar xvzf - -C /opt/conda/bin gh_${GITHUB_CLI_VERSION}_linux_amd64/bin/gh --strip-components=2

# Print Jupyter server token when terminal is opened
RUN echo "echo \"Jupyter server token: \$(jupyter server list 2>&1 | grep -oP '(?<=token=)[[:alnum:]]*')\"" > ${HOME}/.get-jupyter-url.sh && \
    echo "sh \${HOME}/.get-jupyter-url.sh" >> ${HOME}/.bashrc
