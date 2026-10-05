FROM ballerina/ballerina:2201.10.0 AS build
WORKDIR /home/ballerina/app
COPY --chown=ballerina:ballerina . .
RUN bal build

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /home/ballerina/app/target/bin/payment_service.jar .
EXPOSE 8084
HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=5 \
  CMD bash -c 'exec 3<>/dev/tcp/localhost/8084 && printf "GET /health HTTP/1.0\r\n\r\n" >&3 && grep -q "200" <&3' || exit 1
ENTRYPOINT ["java", "-jar", "payment_service.jar"]
