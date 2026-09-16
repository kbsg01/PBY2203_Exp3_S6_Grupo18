#!/usr/bin/env bash
# Funciones compartidas por los scripts de evidencia/pruebas de este proyecto. No se ejecuta
# directamente: se importa con "source scripts/_common.sh".

es_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

# Detiene un proceso por PID de forma confiable tanto en Linux/macOS como en Windows (Git Bash).
# En Git Bash, "kill" sobre un proceso nativo (java.exe, no un binario MSYS) a veces no reporta
# error pero tampoco termina el proceso realmente; "taskkill //F" si lo hace de forma consistente.
detener_pid() {
  local pid="$1"
  [ -z "$pid" ] && return 0
  if es_windows; then
    taskkill //PID "$pid" //F >/dev/null 2>&1 || true
  else
    kill "$pid" >/dev/null 2>&1 || true
  fi
}

# Encuentra el PID de un proceso Java lanzado con "java -jar <patron>...jar", usando jps (viene
# con el JDK, por lo que funciona igual en Linux, macOS y Windows sin depender de pgrep/ps -
# pgrep en particular no existe en Git Bash).
pid_de_jar() {
  local patron="$1"
  jps -l | grep "$patron" | awk '{print $1}' | head -n1
}
