# Image Java 17 officielle (remplace openjdk)
FROM eclipse-temurin:17-jdk-jammy

# Dossier de travail
WORKDIR /app

# Copier le jar compilé
COPY target/spring-petclinic-2.1.0.BUILD-SNAPSHOT.jar app.jar

# Port exposé
EXPOSE 8085

# Lancer l'application
ENTRYPOINT ["java","-jar","app.jar"]
