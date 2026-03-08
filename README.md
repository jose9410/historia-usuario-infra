# Koncilia - Infraestructura y GitOps

Este repositorio contiene la configuración de infraestructura como código (IaC) para el sistema **Koncilia**, utilizando **Kubernetes**, **Helm** y **Argo CD** bajo el patrón GitOps.

## 🏗️ Arquitectura del Sistema

El sistema sigue un modelo de **App of Apps** para gestionar múltiples microservicios y componentes de infraestructura de manera centralizada.

### Componentes Principales

- **Kubernetes**: Clúster base desplegado en Azure VM (v1.30+).
- **Argo CD**: Motor de GitOps que sincroniza el estado de este repositorio con el clúster.
- **Nginx Ingress Controller**: Gestiona el tráfico entrante y el ruteo hacia el frontend y backend.
- **Helm Charts**: Definiciones empaquetadas de las aplicaciones.

## 📁 Estructura del Repositorio

- `charts/`: Contiene los Helm Charts de las aplicaciones.
  - `historia-usuario-api/`: Backend .NET con soporte para IA y persistencia.
  - `historia-usuario-web/`: Frontend Angular 19.
- `argo-apps/`: Manifiestos de `Application` de Argo CD para el patrón App of Apps.
- `.github/workflows/`: Pipelines de validación de infraestructura.

## 🔐 Gestión de Secretos y Persistencia

### Secretos Manuales
Para mantener la seguridad, las credenciales sensitivas (como Azure OpenAI) se gestionan mediante secretos manuales en el clúster:
- Secret Name: `historia-api-manual-secrets`

### Persistencia
Se utiliza almacenamiento tipo `hostPath` vinculado a la VM de Azure en `/data/koncilia/outputs`, garantizando que los archivos generados sobrevivan a reinicios de pods mediante PV y PVC.

## 🚀 Flujo de Despliegue (GitOps)

1. Un cambio es pusheado a la rama `main` de este repositorio.
2. Argo CD detecta el cambio automáticamente.
3. El estado del clúster se sincroniza para coincidir con la definición en Git.

---
© 2026 Koncilia Automation. Todos los derechos reservados.
