## 0311AT – K8S: Casi como en producción

# Contexto
Te sumás como ingeniero DevOps Jr. a un equipo de desarrollo de una pequeña empresa que necesita desplegar un entorno de trabajo para que el equipo de desarrollo pueda trabajar con la versión de contenido estático de su página web institucional. Como parte de tu primer trabajo, deberás confeccionar un entorno de trabajo en forma local en Minikube, con manifiestos de despliegue de aplicaciones, almacenamiento persistente y uso de Git y GitHub, y documentar todo el proceso con el objeto de pasarle dicha documentación al resto del equipo de desarrolladores de la empresa para que puedan trabajar en dicho entorno.
Se debe de tener en cuenta que la aplicación debe poder servirse por navegador en forma local, con
contenido propio (no el default de la plantilla), el cual estará alojado en un volumen persistente que se mantenga incluso si la aplicación se reinicia, pero que la misma debe estar vinculada al repositorio de git de su cuenta de Github.

--

# Preparación de entorno de trabajo
Requisitos a tener en cuenta para realizar el trabajo:
  - Minikube instalado y en funcionamiento.
  - Cuenta de GitHub activa .
  - Docker Desktop instalado y en funcionamiento.
  - Visual Studio instalado.
--
# Paso a paso para producir el entorno completo 
Los siguientes pasos explicados, serán trabajados desde el Power Shell ejecutandolo como Administrador.
También debo tener abierto mi aplicación Docker Desktop para que pueda dar inicio al cluster 

1.Iniciar nuevo cluster de minikube
  ```bash
    minikube start --driver=docker
  ```
2.Verificar que el cluster esté activo haciendo uso de la herramienta de línea de comandos kubectl 
   ```bash
    kubectl get nodes
   ```
3.Crear carpetas locales 
   ```bash
      mdkir CloudTD
      cd ~/CloudTD
      mkdir static-website
      mkdir k8s-manifests
   ```
4. Crear las subcarpetas dentro de k8s-manifests, para los manifiestos.
    ```bash
    cd k8s-manifests
    mkdir deployments,services,volumes
    ```
# Entorno GitHub
Hacer fork del repositorio base, para poder personalizar el mismo con lo que uno desee, para ello debe:
1.Debe estar ubicado en su carpeta CloudTD
 ```bash
    cd ../static-website
 ```
2. Hacer fork del repositorio base `https://github.com/ewojjowe/static-website` en su cuenta activa de GitHub.
3. Una vez hecho el fork, copiar URL del repositorio en creado en tu cuenta para posteriormente clonarlo e inicializarlo
    ```bash
    cd ~/CloudTD/static-website
    git clone https://turepositoriogithub/static-website
    git init
     ```
# Personalizacion del sitio web
Abrir Visual Studio Code para comenzar a editar los archivos del sitio web.Desde la terminal propia de visual studio acceso a los contenidos del repositorio clonado
1. Abrir Visual Studio
2. Haciendo uso de la terminal de Visual Studio, moverse a la carpeta donde se haya clonado el repositorio base
    ```terminal
    cd ~/CloudTD/static-website
    code .
     ```
4. Personalizar sitio web, una vez realizado hacer commit a la rama principal de todas las modificaciones
En mi caso, elimine todo el contenido y reescribi nuevamente todo el html, css y la carpeta assets. Como se trata de un proyecto personal y no colaborativo, al hacer commit aplique un force para reemplazar todo los archivos del repositorio base a todo el contenido que yo misma edite.
 - Agregar archivos html y css
 - Subir archivos al repositorio
 - Agregar archivo asset con imagenes
 - Subir archivo al repositorio
   
 ```bash
    git add index.html style.css
    git commit -m "Personalizacion del sitio web"
    git push origin master --force
    git add assets
    git commit -m "Agrego carpeta assets con imagenes"
    git push origin master
 ```
--
# Preparar manifiestos 
Dentro de la carpeta k8s-manifests, ubicarse en cada subcarpeta correspondiente para crear los yaml.
### Volumenes Persistentes
1. Moverse a la carpeta volumes y crear pv.yaml
   ```bash
    cd k8s-manifests/volumes
    New-Item -Path . -Name "pv.yaml" -ItemType "File"
    ```
El yaml en primera instancia se creará vacío, para ello se deberá completar manualmente.
Para poder acceder al archivo pv.yaml, repetimos el mismo proceso de usar terminal de visual studio para acceder
   ```bash
     cd ~/CloudTD/k8s-manifests/volumes
     code .
   ```
Completar pv.yaml con: 
 ```bash
   apiVersion: v1
kind: PersistentVolume
metadata:
  name: static-pv
spec:
  storageClassName: ""
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/c/Users/Usuario/rutadetucarpeta"
 ```
Repetir mismo proceso y crear y completar pvc.yaml
 ```bash
  apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: static-pvc
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
 ```
2. Aplicar cambios y verificar su ejecución
```bash
   kubectl apply -f
   kubeclt get pv,pvc
 ```

###Deployment
1.Moverse a la carpeta deployment y crear su archivo yaml.
```bash
  cd ../deployments
kubectl create deployment static-website-deployment --image=nginx --dry-run=client -o yaml > deployment.yaml
 ```
2. Edito el yaml solo para agregar puerto y volumen, deberia quedar de la siguiente manera:
   ```bash
   apiVersion: apps/v1
    kind: Deployment
    metadata:
    creationTimestamp: null
    labels:
    app: static-website-deployment
    name: static-website-deployment
    spec:
    replicas: 1
    selector:
    matchLabels:
      app: static-website-deployment
    template:
    metadata:
      creationTimestamp: null
      labels:
        app: static-website-deployment
    spec:
      containers:
      - image: nginx
        name: nginx
        ports:
        - containerPort: 80
        volumeMounts:
        - name : static-content
          mountPath: /usr/share/nginx/html
      volumes:
      - name: static-content
        persistentVolumeClaim:
           claimName: static-pvc
   ```
3. Aplicar cambios y verificar nuevamente
```bash
   kubectl apply -f
   kubeclt get deployments
 ```
###Service
1.Moverse a carpeta services, crear archivo yaml y solo verificar.En este yaml no se hara ninguna edicion
```bash
    cd ../services
    kubectl expose deployment static-website-deployment --port=80 --target-port=80 --type=NodePort --dry-run=client -o yaml > service.yaml
    kubectl apply -f .
    kubectl get services
 ```
El yaml luce asi:
```bash
apiVersion: v1
kind: Service
metadata:
  creationTimestamp: null
  labels:
    app: static-website-deployment
  name: static-website-deployment
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: static-website-deployment
  type: NodePort
status:
  loadBalancer: {}
 ```
# Crear repositorio para k8s-manifests
1. Desde GitHUb crear manualmente un nuevo repositorio llamado k8s-manifests 
2.Desde powershell, ubicarse nuevamente en tu carpeta local k8s-manifests , inicializarla con git y enviar el repositorio con el que se vincula para guardar los manifiestos realizados.
```bash
    cd ..
    git init
    git remote add origin https://turepositorio/k8s-manifests.git
 ```
3.Subir los yaml creados 
```bash
   git add.
   git commit -m "Agrego manifiestos kubernetes"
  git push origin master
 ```

# Despligue de la pagina web
1.Para evitar problemas de lectura de ruta o permisos, se debe seguir la siguiente serie de pasos para un despliegue exitoso de tu sitio web:
 - Eliminar el cluster donde se estaba trabajando 
 - Volver a montar el minikube pero esta vez usando el hostPath donde esta nuestro html. El hostPath lo obtienes de tu pv.yaml
```bash
 minikube delete 
minikube start --driver=docker --mount --mount-string="$HOME/rutadondeestestrabajando:/mnt/c/Users/Usuario/rutadelHostPath"
 ```
2.Aplicar nuevamente todos los manifiestos 
  ```bash
kubectl apply -f volumes/.
kubectl apply -f deployments/.
kubectl apply -f services/.

 ```
3.Verificar la ejecucion de los mismos 
  ```bash
  kubectl get pods
	kubectl get pv,pvc
	kubectl describe pods
	kubectl get deployments 


 ```

4. Para desplegar el servicio, al hacer uso del comando kubectl get pods , en READY debe estar en 1/1. Caso contrario aun no esta listo el servicio para ser desplegado. 
5.Para desplegar el sitio web usar:
 ```bash
 minikube service static-website-deployment
 ```
Y LISTO! Sitio web desplegado.




