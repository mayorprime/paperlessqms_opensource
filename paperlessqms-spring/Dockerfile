# Stage 1: Build Angular frontend
FROM node:20-alpine AS angular-build
WORKDIR /client
COPY paperlessqms-spring-client/package*.json ./
RUN npm ci --prefer-offline
COPY paperlessqms-spring-client/ ./
RUN npm run webapp:prod

# Stage 2: Build Spring Boot backend
FROM eclipse-temurin:22-jdk-alpine AS spring-build
WORKDIR /app
COPY paperlessqms-spring/ ./
# Copy Angular build into Spring's static resources so it gets bundled into the JAR
COPY --from=angular-build /client/target/classes/static/ src/main/resources/static/
RUN chmod +x mvnw && ./mvnw package -DskipTests --no-transfer-progress

# Stage 3: Minimal runtime image
FROM eclipse-temurin:22-jre-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=spring-build /app/target/*.jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
