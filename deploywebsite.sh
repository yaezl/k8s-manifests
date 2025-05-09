#!/bin/bash
#################################################
# deploywebsite.sh
# Alumna: Yael Zuna
#
#Script para automatizar el despliegue de un sitio web estatico personalizados
# en Minikube utilizando manikifestos kubernetes
####################################################3

# Fail Fast - Detener el script en caso de error 
set -e
set -o pipefail

#Variables de configuracion 
USUARIO_GITHUB="${1:-yaezl}"
BASE_DIR="$HOME/CloudTD"
WEBSITE_DIR="$BASE_DIR/static-website"
K8S_DIR="$BASE_DIR/k8s-manifests"
GITHUB_WEBSITE_REPO="https://github.com/$USUARIO_GITHUB/static-website.git"
GITHUB_K8S_REPO="https://github.com/$USUARIO_GITHUB/k8s-manifests.git"


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

    command -v minikube >/dev/null 2>&1 || log_error "Minikube no está instalado. Por favor, instálalo antes de continuar."
    command -v kubectl >/dev/null 2>&1 || log_error "Kubectl no está instalado. Por favor, instálalo antes de continuar."
    command -v git >/dev/null 2>&1 || log_error "Git no está instalado. Por favor, instálalo antes de continuar."

    # Verificar que Docker esté en ejecución 
    docker info >/dev/null 2>&1 || log_error "Docker no está en ejecución. Por favor inicia Docker Desktop antes de continuar."

    log_info "Todas las dependencias están instaladas correctamente."
}

#Funcion para crear la estructura de directorios 
create_directories(){
    log_info "Creando estructura de directorios..."

    # Crear directorio base si no existe 
    mkdir -p "$BASE_DIR"

    # Crear directorios para el sitio web y los manifiestos 
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
    log_warning "Eliminando perfil de Minikube existente..."
    minikube delete || true
    
    log_info "Iniciando Minikube con montaje del directorio del sitio web..."
    minikube start --driver=docker --mount --mount-string="$WEBSITE_DIR:/mnt/web/static-website"

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
    
    log_info "Contenido actual del archivo PV:"
    cat "$PV_FILE"
    
    # Crear un archivo temporal para realizar modificaciones
    PV_TEMP=$(mktemp)
    
    # Actualizar la ruta del hostPath en el archivo pv.yaml
    sed "s|path:.*|path: \"/mnt/web/static-website\"|g" "$PV_FILE" > "$PV_TEMP"
    
    # Verificar que la sustitución se realizó correctamente
    if ! grep -q "path: \"/mnt/web/static-website\"" "$PV_TEMP"; then
        log_warning "No se pudo actualizar automáticamente la ruta. Editando manualmente..."
        # Intenta un enfoque diferente si la expresión regular no funciona
        cat "$PV_FILE" | awk '{
            if ($0 ~ /hostPath:/) {
                print $0;
                print "    path: \"/mnt/web/static-website\"";
                getline; # Saltar la línea original de path
            } else {
                print $0;
            }
        }' > "$PV_TEMP"
    fi
    
    mv "$PV_TEMP" "$PV_FILE"
    
    log_info "Ruta del PersistentVolume actualizada a: /mnt/web/static-website"
    log_info "Contenido actualizado del archivo PV:"
    cat "$PV_FILE"
}

# Función para aplicar los manifiestos
apply_manifests() {
    log_info "Aplicando manifiestos de Kubernetes..."
    
    # Aplicar manifiestos en el orden correcto: PV, PVC, Deployment, Service
    log_info "Aplicando PersistentVolume..."
    kubectl apply -f "$K8S_DIR/volumes/pv.yaml"
    kubectl get pv
    
    log_info "Aplicando PersistentVolumeClaim..."
    kubectl apply -f "$K8S_DIR/volumes/pvc.yaml"
    kubectl get pvc
    
    log_info "Aplicando Deployment..."
    kubectl apply -f "$K8S_DIR/deployments/deployment.yaml"
    
    # Verificar que el deployment se haya creado
    if ! kubectl get deployment static-website-deployment >/dev/null 2>&1; then
        log_error "No se pudo crear el deployment. Verificando el archivo..."
        cat "$K8S_DIR/deployments/deployment.yaml"
        log_error "Deployment no encontrado después de aplicar el manifiesto."
    fi
    
    kubectl get deployments
    
    log_info "Aplicando Service..."
    kubectl apply -f "$K8S_DIR/services/service.yaml"
    kubectl get services
    
    log_info "Manifiestos aplicados correctamente."
}

# Función para esperar a que los pods estén listos
wait_for_pods() {
    log_info "Esperando a que los pods estén listos..."

    # Esperar que el pod se cree primero
    COUNTER=0
    MAX_ATTEMPTS=30
    
    while [ $COUNTER -lt $MAX_ATTEMPTS ]; do
        if kubectl get pods -l app=static-website-deployment 2>/dev/null | grep -q "static-website"; then
            log_info "Pod encontrado. Esperando a que esté listo..."
            break
        fi
        log_warning "Esperando que el pod se cree... (${COUNTER}/${MAX_ATTEMPTS})"
        sleep 5
        COUNTER=$((COUNTER+1))
    done
    
    if [ $COUNTER -eq $MAX_ATTEMPTS ]; then
        log_error "No se encontró ningún pod después de 150 segundos. Verificando estado del despliegue..."
        kubectl get deployments
        kubectl describe deployment static-website-deployment
        exit 1
    fi

    # Ahora esperar a que el pod esté listo
    COUNTER=0
    
    while [ $COUNTER -lt $MAX_ATTEMPTS ]; do
        POD_STATUS=$(kubectl get pods -l app=static-website-deployment -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        READY_STATUS=$(kubectl get pods -l app=static-website-deployment -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
        
        if [ "$POD_STATUS" = "Running" ] && [ "$READY_STATUS" = "true" ]; then
            log_info "¡Pod listo y en ejecución!"
            break
        fi
        
        log_warning "Pod en estado: $POD_STATUS, Ready: $READY_STATUS. Esperando... (${COUNTER}/${MAX_ATTEMPTS})"
        sleep 5
        COUNTER=$((COUNTER+1))
    done
    
    if [ $COUNTER -eq $MAX_ATTEMPTS ]; then
        log_error "El pod no entró en estado Ready después de 150 segundos. Verificando problemas..."
        kubectl describe pod -l app=static-website-deployment
        exit 1
    fi

    # Mostrar información de los recursos desplegados
    log_info "Mostrando recursos desplegados:"
    kubectl get pods
    kubectl get deployments
    kubectl get services
    
    # Verificar montaje del volumen
    log_info "Verificando el montaje del volumen..."
    if kubectl exec deploy/static-website-deployment -- ls /usr/share/nginx/html/index.html >/dev/null 2>&1; then
        log_info "El volumen está montado y el sitio fue cargado en el contenedor."
    else
        log_warning "No se encontró el archivo index.html en el contenedor."
        kubectl exec deploy/static-website-deployment -- ls -la /usr/share/nginx/html/ || true
    fi
}

# Función para exponer el servicio
expose_service() {
    log_info "Exponiendo el servicio..."
    minikube service static-website-deployment &
    sleep 3
    log_info "Despliegue finalizado correctamente. ¡Tu sitio está online!"
}
# Funcion principal
main(){
    log_info "Iniciando despliegue del sitio web estático en Minikube..."

    check_dependencies
    create_directories
    clone_repositories
    restart_minikube
    update_pv_path
    apply_manifests
    wait_for_pods
    expose_service
}
#Ejecutar funcion principal
main "$@"

#Para ejecutar este script
# bash deploywebsite.sh
