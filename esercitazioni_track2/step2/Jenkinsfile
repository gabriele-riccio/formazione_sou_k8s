pipeline {
    agent any

    environment {
        DOCKERHUB_USER     = 'gabbogr71809'
        IMAGE_NAME         = "{DOCKERHUB_USER}/flask-app-example"
        DOCKERHUB_CREDS_ID = 'dockerhub-credentials'

    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Determine Tag') {
            steps {
                script {
                    def gitTag    = sh(script: "git tag --points-at HEAD", returnStdout: true).trim()
                    def gitBranch = env.GIT_BRANCH.replaceALL('origin/','')?:''
                    def gitSHA    = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()

                    if (gitTAG) {
                        env.DOCKER_TAG = gitTAG
                        echo "Build da tag Git - ${env.DOCKER_TAG}"
                    } else if
