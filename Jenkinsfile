pipeline {

    agent any

    tools {
        maven 'M3'
    }
    parameters {
        choice(name: 'SCAN_TYPE', choices: ['Baseline','APIS','Full'], description: 'Type de scan ZAP')
        string(name: 'TARGET', defaultValue: 'http://host.docker.internal:8080', description: 'URL cible')
        booleanParam(name: 'GENERATE_REPORT', defaultValue: true, description: 'Generate ZAP report')
    }

    environment {
        LOG_FILE = "pipeline-report.txt"
        SONAR_PROJECT_KEY = "petCliniqueProj"
        SONAR_HOST_URL = "http://host.docker.internal:9003"
        SONAR_TOKEN = credentials('SONAR_TOKEN')
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'master',
                    url: 'https://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@github.com/DeveloperM107/SpringPetClinique.git'
            }
        }

        stage('Build') {
            steps {
                sh 'mvn compile'
            }
        }

        stage('Test') {
            steps {
                sh 'mvn test'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                echo "Lancement analyse SonarQube..."
                sh """
                mvn sonar:sonar \
                -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                -Dsonar.host.url=${SONAR_HOST_URL} \
                -Dsonar.login=${SONAR_TOKEN}
                """
            }
        }

     stage('OWASP ZAP') {
 steps {
  sh '''
 docker run --rm \
  --network infra_devops-net \
  -u root \
  -v "$PWD:/zap/wrk" \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py \
  -t http://jenkins:8080 \
  -r zap-report.html \
  -J zap-report.json \
  -I \
  --autooff
  '''
 }
}
       stage('Publish ZAP Report') {
 steps {
  publishHTML(target: [
    allowMissing: true,
    alwaysLinkToLastBuild: true,
    keepAll: true,
    reportDir: '.',
    reportFiles: 'zap-report.html',
    reportName: 'OWASP ZAP Report'
  ])
 }
}

    }

}
