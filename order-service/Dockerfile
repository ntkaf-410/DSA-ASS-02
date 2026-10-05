FROM ballerina/ballerina:2201.10.0 AS build
USER root
WORKDIR /app
COPY . .
RUN bal build

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/bin/order_service.jar /app/order_service.jar
EXPOSE 8083
CMD ["java", "-jar", "/app/order_service.jar"]
