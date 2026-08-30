import json
import logging
import boto3
import re
from datetime import datetime, timedelta

# Configurar el logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Inicializar clientes de boto3
cloudwatch_client = boto3.client('cloudwatch')
logs_client = boto3.client('logs')

# Nombres de las alarmas a correlacionar
ALARM_LATENCY = "data-service-high-latency-p99"
ALARM_ERRORS = "data-service-anomaly-errors"
LOG_GROUP_NAME = "/ecs/data-service"

def get_alarm_state(alarm_name):
    """Obtiene el estado actual de una alarma de CloudWatch."""
    try:
        response = cloudwatch_client.describe_alarms(AlarmNames=[alarm_name])
        if response['MetricAlarms']:
            return response['MetricAlarms'][0]['StateValue']
        elif response['CompositeAlarms']:
            return response['CompositeAlarms'][0]['StateValue']
    except Exception as e:
        logger.error(f"Error al obtener el estado de la alarma {alarm_name}: {e}")
    return "UNKNOWN"

def find_trace_id_in_logs():
    """Busca el último error en CloudWatch Logs y extrae el Trace ID de OpenTelemetry."""
    end_time = int(datetime.utcnow().timestamp() * 1000)
    start_time = int((datetime.utcnow() - timedelta(minutes=10)).timestamp() * 1000)
    
    query = "fields @timestamp, @message | filter @message like /(?i)error|exception|fail/ | sort @timestamp desc | limit 5"
    
    try:
        # Iniciamos la consulta en Logs Insights
        start_query_response = logs_client.start_query(
            logGroupName=LOG_GROUP_NAME,
            startTime=start_time,
            endTime=end_time,
            queryString=query
        )
        query_id = start_query_response['queryId']
        
        # Esperar a que la consulta termine (bucle simple)
        response = None
        import time
        for _ in range(5):
            time.sleep(2)
            response = logs_client.get_query_results(queryId=query_id)
            if response['status'] == 'Complete':
                break
        
        if response and response['status'] == 'Complete':
            for result in response['results']:
                # El resultado es una lista de diccionarios con 'field' y 'value'
                message = next((item['value'] for item in result if item['field'] == '@message'), "")
                
                # Buscar un TraceId típico de OpenTelemetry (32 caracteres hexadecimale), e.g. TraceId: 0af7651916cd43dd8448eb211c80319c
                # O formato JSON estructurado: "traceId":"0af7..."
                match = re.search(r'(?:trace_id|traceid|trace-id)[\s\'":]+([a-f0-9]{32})', message, re.IGNORECASE)
                if match:
                    return match.group(1)
                
    except Exception as e:
        logger.error(f"Error buscando Trace ID en los logs: {e}")
        
    return "Trace ID no encontrado en los últimos 10 minutos"


def lambda_handler(event, context):
    """Punto de entrada de la Lambda invocado por SNS."""
    logger.info(f"Evento recibido: {json.dumps(event)}")
    
    # Extraer el mensaje de la alarma de SNS
    try:
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        triggering_alarm = sns_message.get('AlarmName', 'UNKNOWN')
        logger.info(f"Lambda disparada por la alarma: {triggering_alarm}")
    except Exception as e:
        logger.error(f"Error al parsear el mensaje de SNS: {e}")
        return {"statusCode": 400, "body": "Invalid SNS event"}

    # Determinar cuál es la otra alarma a revisar
    other_alarm = ALARM_ERRORS if triggering_alarm == ALARM_LATENCY else ALARM_LATENCY
    
    # Obtener el estado de la otra alarma
    other_alarm_state = get_alarm_state(other_alarm)
    logger.info(f"Estado de la alarma compañera ({other_alarm}): {other_alarm_state}")
    
    # Correlacionar
    # Si ambas están en ALARM, se confirma la degradación total.
    if other_alarm_state == "ALARM":
        logger.warning(f"CORRELACIÓN POSITIVA: Las alarmas {triggering_alarm} y {other_alarm} están activas simultáneamente.")
        
        # Extraer el Trace ID de OpenTelemetry
        trace_id = find_trace_id_in_logs()
        
        # Construir y enviar alerta enriquecida
        alert_payload = {
            "severity": "CRITICAL",
            "message": "⚠️ ALERTA CORRELACIONADA: Degradación severa del Servicio (Latencia + Anomalía de Errores detectada).",
            "service": "data-service",
            "trigger_1": triggering_alarm,
            "trigger_2": other_alarm,
            "trace_id_example": trace_id,
            "action_required": "Revisar inmediatamente el Trace ID en Jaeger/X-Ray o revisar logs de Base de Datos."
        }
        
        # Aquí se podría publicar a un webhook de Slack, PagerDuty, o reenviar a otro tópico SNS.
        # Por ahora lo imprimimos como log estructurado que puede ser absorbido por un sistema de monitoreo.
        logger.error(json.dumps(alert_payload))
        
        return {"statusCode": 200, "body": "Correlated alert sent successfully"}
    
    else:
        logger.info("No hay correlación. La degradación parece ser aislada (solo latencia o solo errores).")
        return {"statusCode": 200, "body": "Single alert logged, no correlation detected."}
