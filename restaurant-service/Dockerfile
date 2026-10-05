# build stage - tag must match `distribution` in Ballerina.toml
FROM ballerina/ballerina:2201.10.0 AS build
WORKDIR /home/ballerina/app
COPY --chown=ballerina:ballerina . .
RUN bal build

# runtime stage
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /home/ballerina/app/target/bin/restaurant_service.jar .
EXPOSE 8082
HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=5 \
  CMD bash -c 'exec 3<>/dev/tcp/localhost/8082 && printf "GET /health HTTP/1.0\r\n\r\n" >&3 && grep -q "200" <&3' || exit 1
ENTRYPOINT ["java", "-jar", "restaurant_service.jar"]
