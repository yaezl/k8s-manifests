#!/bin/bash
#################################################
# deploy_website.sh
# Alumna: Yael Zuna
# Version 1.0
#
#Script para automatizar el despliegue de un sitio web estatico personalizados
#en Minikube utilizando manikifestos kubernetes
####################################################3

# Fail Fast - Detener el script en caso de error 
set -e
set -o pipefail

#Variables de configuracion 
GITHUB_WEBSITE_REPO="https://github.com/yaezl/static-website.git"
GITHUB_K8S_REPO="https://github.com/yaezl/k8s-manifests.git"
BASE_DIR="$HOME/CloudTD"
WEBSITE_DIR="$BASE_DIR/static-website"
K8S_DIR="$BASE_DIR/k8s-manifests"
HOSTPATH="/mnt/c/Users/Usuario/CloudTD/static-website"

#Colores para mensajes 
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' 

#Funcion para mostrar mensajes informativos 
log_info(){
    echo -e "${GREEN}[INFO]${NC} $1"
}

#Funcion para mostrar advertencias 
log_warning(){
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

#Funcion para mostrar errores
log_error(){
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}
#Funcion para verificar dependencias 
check_dependencies(){
    log_info "Verificando dependencias..."

    command -v minikube >/dev/null 2>&1 || log_error "Minikube no esta instalado.Por favor, instalalo antes de continuar."
    command -v kubectl >/dev/null 2>&1 || log_error "Kubectl no está instalado. Por favor, instálalo antes de continuar."
    command -v git >/dev/null 2>&1 || log_error "Git no está instalado. Por favor, instálalo antes de continuar."

    #Verificar que Docker esté en ejecucion 
    docker info >/dev/null 2>&1 || log_error "Docker no está en ejecucuion.Por favor inicia Docker Desktop antes de continuar."

    log_info "Todas las dependencias están instaladas correctamente"

}

#Funcion para crear la estructura de directorios 
create_directories(){
    log_info "Creando estructura de directorios..."

    #crear directorio base si no existe 
    mkdir -p "$BASE_DIR"

    #crear directorios para el sitio web y los manifiestos 
    mkdir -p "$WEBSITE_DIR"
    mkdir -p "$K8S_DIR"
    mkdir -p "$K8S_DIR/deployments"
    mkdir -p "$K8S_DIR/services"
    mkdir -p "$K8S_DIR/volumes"
    
    log_info "Estructura de directorios creada exitosamente."

}
#Funcion para clonar los repositorios 
clone_repositories(){
    log_info "Clonando repositorios..."

    # --- sitio web ---
    if [ -d "$WEBSITE_DIR/.git" ]; then
        log_warning "El repositorio del sitio web ya existe. Actualizando..."
        cd "$WEBSITE_DIR"
        BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
        git pull origin "$BRANCH"
    else
        [ -d "$WEBSITE_DIR" ] && rm -rf "$WEBSITE_DIR"
        git clone "$GITHUB_WEBSITE_REPO" "$WEBSITE_DIR"
    fi

    # --- manifiestos K8s ---
    if [ -d "$K8S_DIR/.git" ]; then
        log_warning "El repositorio de manifiestos K8s ya existe. Actualizando..."
        cd "$K8S_DIR"
        BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
        git pull origin "$BRANCH"
    else
        [ -d "$K8S_DIR" ] && rm -rf "$K8S_DIR"
        git clone "$GITHUB_K8S_REPO" "$K8S_DIR"
    fi

    log_info "Repositorios clonados exitosamente."
}



#Funcion para reiniciar Minikube con la configuracion correcta 

restart_minikube(){
    log_info "Reiniciando Minikube..."

    # Detener Minikube si está en ejecución
    if minikube status >/dev/null 2>&1; then
        log_warning "Minikube está en ejecución. Deteniéndolo..."
        minikube delete
    fi
    
    # Iniciar Minikube con la configuración correcta
    log_info "Iniciando Minikube con montaje del directorio del sitio web..."
    minikube start --driver=docker --mount --mount-string="/mnt/c/Users/Usuario/CloudTD/static-website:/mnt/data"


    # Verificar que Minikube se haya iniciado correctamente
    if ! minikube status >/dev/null 2>&1; then
        log_error "Error al iniciar Minikube. Verifica la configuración y vuelve a intentarlo."
    fi
    
    log_info "Minikube iniciado exitosamente."
}
# Función para actualizar la ruta en el archivo PV
update_pv_path() {
    log_info "Actualizando la ruta del PersistentVolume..."
    
    # Archivo PV
    PV_FILE="$K8S_DIR/volumes/pv.yaml"
    
    # Verificar que el archivo existe
    if [ ! -f "$PV_FILE" ]; then
        log_error "No se encontró el archivo pv.yaml. Verifica la estructura del repositorio."
    fi
    
    # Crear un archivo temporal para realizar modificaciones
    PV_TEMP=$(mktemp)
    
    # Actualizar la ruta del hostPath en el archivo pv.yaml
    sed "s|path: .*|path: \"/mnt/data\"|g" "$PV_FILE" > "$PV_TEMP"
    mv "$PV_TEMP" "$PV_FILE"
    
    log_info "Ruta del PersistentVolume actualizada correctamente."
}

# Función para aplicar los manifiestos
apply_manifests() {
    log_info "Aplicando manifiestos de Kubernetes..."
    
    # Aplicar manifiestos en el orden correcto: PV, PVC, Deployment, Service
    kubectl apply -f "$K8S_DIR/volumes/pv.yaml"
    kubectl apply -f "$K8S_DIR/volumes/pvc.yaml"
    kubectl apply -f "$K8S_DIR/deployments/deployment.yaml"
    kubectl apply -f "$K8S_DIR/services/service.yaml"
    
    log_info "Manifiestos aplicados correctamente."
}

# Función para esperar a que los pods estén listos
wait_for_pods() {
    log_info "Esperando a que los pods estén listos..."

    COUNTER=0
    MAX_ATTEMPTS=50

    while [ $COUNTER -lt $MAX_ATTEMPTS ]; do
        POD_COUNT=$(kubectl get pods -l app=static-website-deployment --no-headers | wc -l)

        if [ "$POD_COUNT" -eq 0 ]; then
            log_warning "No se encontró ningún pod con la etiqueta app=static-website-deployment. Esperando 10 segundos..."
        else
            POD_STATUS=$(kubectl get pods -l app=static-website-deployment -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)

            if [ "$POD_STATUS" == "true" ]; then
                log_info "¡Pod listo!"
                break
            fi

            log_warning "Pod aún no está listo. Intentando de nuevo en 10 segundos..."
        fi

        sleep 10
        COUNTER=$((COUNTER+1))
    done

    if [ $COUNTER -eq $MAX_ATTEMPTS ]; then
        log_error "Tiempo de espera agotado. El pod no está listo después de 5 minutos."
    fi
}



# Función para exponer el servicio
expose_service() {
    log_info "Exponiendo el servicio..."

    # Obtener URL del servicio 
    SERVICE_URL=$(minikube service static-website-deployment --url 2>/dev/null)&

    if [ -z "$SERVICE_URL" ]; then
        log_error "No se pudo obtener la URL del servicio. Acceda manualmente al servicio con : minikube service static-website-deployment"
        return 1
    fi

    # Guardar la URL en un archivo
    echo "$SERVICE_URL" > "$BASE_DIR/URL_despliegue.txt"
    log_info "¡Sitio web desplegado exitosamente!"
    log_info "URL guardada en $BASE_DIR/URL_despliegue.txt"
    log_info "Para acceder al sitio web, abre la siguiente URL en tu navegador:"
    echo -e "${GREEN}$SERVICE_URL${NC}"

}



# Funcion principal
main(){
    log_info "Iniciando despliegue del sitio web estatico en Minikube..."
    
    #Ejecutar funciones en orden 
    check_dependencies
    create_directories
    clone_repositories
    restart_minikube
    update_pv_path
    apply_manifests
    wait_for_pods
    expose_service
}

main "$@"
