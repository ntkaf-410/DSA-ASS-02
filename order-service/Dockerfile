FROM ballerina/ballerina:2201.10.0 AS build
USER root
WORKDIR /app
COPY . .
RUN bal build

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/bin/order_service.jar /app/order_service.jar
EXPOSE 8083
# Override with BAL_CONFIG_VAR_DBHOST=mysql, BAL_CONFIG_VAR_KAFKABOOTSTRAP=kafka:9092, etc.
CMD ["java", "-jar", "/app/order_service.jar"]
