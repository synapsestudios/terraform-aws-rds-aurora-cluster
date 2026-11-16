# AWS Emulator in a container, for machines without the Linux package.
# AWS publishes no image, so this installs the pinned RPM.
FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal

ARG EMULATOR_VERSION
ARG TARGETARCH

RUN arch=$([ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64) \
  && curl -fsSLo /tmp/aws-emulator.rpm "https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/aws-emulator-${EMULATOR_VERSION}-1-${arch}.rpm" \
  && rpm -i /tmp/aws-emulator.rpm \
  && rm /tmp/aws-emulator.rpm \
  && mkdir -p /home/emulator \
  && chown 1000 /home/emulator

USER 1000
ENV HOME=/home/emulator EMULATOR_TELEMETRY=off
EXPOSE 9297
ENTRYPOINT ["aws-emulator", "-b", "0.0.0.0", "--telemetry", "off"]
