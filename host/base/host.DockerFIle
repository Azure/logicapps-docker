ARG HOST_VERSION=4.27.3
ARG JAVA_VERSION=8u362b09
ARG JDK_NAME=jdk8u362-b09
ARG JAVA_HOME=/usr/lib/jvm/adoptium-8-x64
FROM mcr.microsoft.com/dotnet/sdk:6.0-jammy AS runtime-image
ARG HOST_VERSION
ARG EXTENSION_BUNDLE_VERSION
ARG JAVA_VERSION
ARG JDK_NAME
ARG JAVA_HOME
ARG EXTENSION_BUNDLE_CDN_URL=https://functionscdn.azureedge.net/public

ENV PublishWithAspNetCoreTargetManifest=false

RUN if [ "$EXTENSION_BUNDLE_CDN_URL" != "https://functionscdn.azureedge.net/public" ] && [ -z "$EXTENSION_BUNDLE_VERSION" ]; then \
        echo 'Error: EXTENSION_BUNDLE_VERSION must be set when EXTENSION_BUNDLE_CDN_URL is not "https://functionscdn.azureedge.net/public"' && exit 1; \
    fi

RUN apt-get update && apt-get install -y curl jq gnupg wget unzip
RUN curl -o response.json "${EXTENSION_BUNDLE_CDN_URL}/ExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/index.json"

RUN if [ -z "$EXTENSION_BUNDLE_VERSION" ]; then \
        EXTENSION_BUNDLE_VERSION=$(jq -r 'max_by(. | split(".") | map(tonumber))' response.json); \
        echo "Using version: $EXTENSION_BUNDLE_VERSION"; \
        EXTENSION_BUNDLE_FILENAME_V4=Microsoft.Azure.Functions.ExtensionBundle.Workflows.${EXTENSION_BUNDLE_VERSION}_any-any.zip; \
        wget $EXTENSION_BUNDLE_CDN_URL/ExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/$EXTENSION_BUNDLE_VERSION/$EXTENSION_BUNDLE_FILENAME_V4; \
        mkdir -p /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/$EXTENSION_BUNDLE_VERSION; \
        unzip /$EXTENSION_BUNDLE_FILENAME_V4 -d /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/$EXTENSION_BUNDLE_VERSION; \
        rm -f /$EXTENSION_BUNDLE_FILENAME_V4; \
    else \
        echo "Using version: $EXTENSION_BUNDLE_VERSION"; \
        EXTENSION_BUNDLE_FILENAME_V4=Microsoft.Azure.Functions.ExtensionBundle.Workflows.${EXTENSION_BUNDLE_VERSION}_any-any.zip; \
        wget $EXTENSION_BUNDLE_CDN_URL/ExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/$EXTENSION_BUNDLE_VERSION/$EXTENSION_BUNDLE_FILENAME_V4; \
        mkdir -p /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/$EXTENSION_BUNDLE_VERSION; \
        unzip /$EXTENSION_BUNDLE_FILENAME_V4 -d /FuncExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/$EXTENSION_BUNDLE_VERSION; \
        rm -f /$EXTENSION_BUNDLE_FILENAME_V4; \
    fi

RUN find /FuncExtensionBundles/ -type f -exec chmod 644 {} \;

RUN BUILD_NUMBER=$(echo ${HOST_VERSION} | cut -d'.' -f 3) && \
    git clone --branch v${HOST_VERSION} https://github.com/Azure/azure-functions-host /src/azure-functions-host && \
    cd /src/azure-functions-host && \
    HOST_COMMIT=$(git rev-list -1 HEAD) && \
    dotnet publish -v q /p:BuildNumber=$BUILD_NUMBER /p:CommitHash=$HOST_COMMIT src/WebJobs.Script.WebHost/WebJobs.Script.WebHost.csproj -c Release --output /azure-functions-host --runtime linux-x64 && \
    mv /azure-functions-host/workers /workers && mkdir /azure-functions-host/workers && \
    rm -rf /root/.local /root/.nuget /src

RUN wget https://github.com/adoptium/temurin8-binaries/releases/download/${JDK_NAME}/OpenJDK8U-jdk_x64_linux_hotspot_${JAVA_VERSION}.tar.gz && \
    mkdir -p ${JAVA_HOME} && \
    tar -xzf OpenJDK8U-jdk_x64_linux_hotspot_${JAVA_VERSION}.tar.gz -C ${JAVA_HOME} --strip-components=1 && \
    rm -f OpenJDK8U-jdk_x64_linux_hotspot_${JAVA_VERSION}.tar.gz

FROM mcr.microsoft.com/dotnet/aspnet:6.0-jammy AS aspnet6

FROM mcr.microsoft.com/dotnet/runtime-deps:6.0-jammy
ARG HOST_VERSION
ARG JAVA_HOME

RUN apt-get update && \
    apt-get install -y curl gnupg && \
    curl -sL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs

ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    HOME=/home \
    DOTNET_USE_POLLING_FILE_WATCHER=true \
    HOST_VERSION=${HOST_VERSION} \
    ASPNETCORE_CONTENTROOT=/azure-functions-host \
    JAVA_HOME=${JAVA_HOME} \
    AzureFunctionsJobHost__extensionBundle__id=Microsoft.Azure.Functions.ExtensionBundle.Workflows \
    AzureFunctionsJobHost__extensionBundle__version=[1.*,2.0.0) \
    APP_KIND=workflowApp \
    FUNCTIONS_EXTENSION_VERSION=~4 \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
    FUNCTIONS_RUNTIME_SCALE_MONITORING_ENABLED=1 \
    MANAGED_ENVIRONMENT=true 

# Fix from https://github.com/GoogleCloudPlatform/google-cloud-dotnet-powerpack/issues/22#issuecomment-729895157
RUN apt-get update && \
    apt-get install -y libc-dev

# Fix from https://github.com/AdoptOpenJDK/blog/blob/ba5844ddc0b7e25d8ae49ac65a8b4e25dea5a48c/content/blog/prerequisites-for-font-support-in-adoptopenjdk/index.md#linux
RUN apt-get update && \
    apt-get install -y libfreetype6 fontconfig fonts-dejavu

# Chrome Headless Dependencies (01/2023)
# https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md#chrome-headless-doesnt-launch-on-unix
RUN apt-get install -y ca-certificates fonts-liberation libasound2 libatk-bridge2.0-0 libatk1.0-0 libc6 \
    libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libgcc1 libglib2.0-0 libgtk-3-0 libnspr4 \
    libnss3 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 \
    libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 lsb-release wget xdg-utils

RUN curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin -Channel 8.0 -Runtime dotnet -InstallDir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

COPY --from=runtime-image [ "/azure-functions-host", "/azure-functions-host" ]
COPY --from=runtime-image [ "/workers/java", "/azure-functions-host/workers/java" ]
COPY --from=runtime-image [ "/workers/node", "/azure-functions-host/workers/node" ]
COPY --from=runtime-image [ "${JAVA_HOME}", "${JAVA_HOME}" ]
COPY --from=runtime-image [ "/FuncExtensionBundles", "/FuncExtensionBundles" ]
COPY --from=aspnet6 [ "/usr/share/dotnet", "/usr/share/dotnet" ]

CMD [ "/azure-functions-host/Microsoft.Azure.WebJobs.Script.WebHost" ]
