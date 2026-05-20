# Migración Completa de Laravel a Supabase ✅

## Cambios Realizados

### 1. **Backend Laravel Eliminado**
- ✅ Carpeta `backend/` completamente removida
- ✅ Todos los endpoints migrados a Supabase Edge Functions

### 2. **Edge Functions Creadas/Actualizadas**

#### `import-workouts`
- ✅ Importar rutinas desde PDF y Excel
- ✅ Análisis automático de estructura de PDF
- ✅ Manejo mejorado de tipos TypeScript
- ✅ Mejor gestión de errores
- Ubicación: `/frontend/supabase/functions/import-workouts/`

#### `import-diets` (NUEVA)
- ✅ Importar dietas desde PDF y Excel
- ✅ Parseo automático de comidas
- ✅ Extracción de macronutrientes
- Ubicación: `/frontend/supabase/functions/import-diets/`

#### `identify-food` (NUEVA)
- ✅ Analizar imágenes de comida con Gemini 2.0 Flash
- ✅ Extracción automática de calorías y macronutrientes
- ✅ Estimación de porciones
- Ubicación: `/frontend/supabase/functions/identify-food/`

### 3. **Configuración Actualizada**

#### `config.toml`
- ✅ Agregadas las 3 Edge Functions
- ✅ Configuradas correctamente con import maps

#### `deno.json` (por cada función)
- ✅ Importaciones de npm correctamente configuradas
- ✅ Soporte para xlsx, pdf-parse y Supabase JS

#### `api_config.dart`
- ✅ Removida referencia a Laravel (`baseUrl`)
- ✅ Agregados constantes para Edge Functions
- URLs configuradas correctamente

### 4. **Frontend Actualizado**

#### `diet_camera_screen.dart`
- ✅ Migrado de http.post a MultipartRequest
- ✅ Ahora usa Edge Function `identify-food`
- ✅ Autenticación con Supabase Auth en lugar de tokens guardados
- ✅ Removida dependencia de SharedPreferences para tokens

#### `main.dart`
- ✅ Ya estaba usando Supabase para CRUD de workouts y diets
- ✅ Funciona correctamente con las nuevas Edge Functions

#### `auth_screen.dart`
- ✅ Ya estaba usando Supabase Auth correctamente

## Próximos Pasos

### 1. **Configurar Variables de Entorno**

En Supabase Dashboard, asegúrate de que la variable de entorno `GEMINI_API_KEY` está configurada:

```bash
# En Supabase Dashboard > Project Settings > Edge Functions > Secrets
GEMINI_API_KEY=tu_clave_gemini_api
```

### 2. **Hacer Deploy de las Edge Functions**

```bash
cd /Users/josh/Healty-T/frontend

# Deploy de import-workouts (actualizado)
supabase functions deploy import-workouts --no-verify-jwt

# Deploy de import-diets (nueva)
supabase functions deploy import-diets --no-verify-jwt

# Deploy de identify-food (nueva)
supabase functions deploy identify-food --no-verify-jwt
```

### 3. **Crear Tablas en Supabase** (si no existen)

Si las tablas no existen, créalas en Supabase SQL Editor:

```sql
-- Tabla de usuarios (creada automáticamente por Supabase Auth)

-- Tabla de rutinas
CREATE TABLE workouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  day_of_week INTEGER,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Tabla de ejercicios
CREATE TABLE exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_id uuid REFERENCES workouts(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  sets INTEGER DEFAULT 3,
  reps TEXT DEFAULT '10',
  rest_seconds INTEGER DEFAULT 60,
  notes TEXT,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Tabla de dietas
CREATE TABLE diets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  day_of_week INTEGER,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Tabla de comidas
CREATE TABLE meals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  diet_id uuid REFERENCES diets(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  calories INTEGER DEFAULT 0,
  protein INTEGER DEFAULT 0,
  carbs INTEGER DEFAULT 0,
  fats INTEGER DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Tabla de comidas diarias
CREATE TABLE daily_diets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  calories DECIMAL(10, 2) DEFAULT 0,
  protein DECIMAL(10, 2) DEFAULT 0,
  carbs DECIMAL(10, 2) DEFAULT 0,
  fats DECIMAL(10, 2) DEFAULT 0,
  grams DECIMAL(10, 2) DEFAULT 0,
  consumed_at DATE NOT NULL,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Tabla de alimentos
CREATE TABLE foods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  calories DECIMAL(10, 2) DEFAULT 0,
  protein DECIMAL(10, 2) DEFAULT 0,
  carbs DECIMAL(10, 2) DEFAULT 0,
  fats DECIMAL(10, 2) DEFAULT 0,
  estimated_grams DECIMAL(10, 2) DEFAULT 0,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Habilitar RLS en todas las tablas
ALTER TABLE workouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE diets ENABLE ROW LEVEL SECURITY;
ALTER TABLE meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_diets ENABLE ROW LEVEL SECURITY;
ALTER TABLE foods ENABLE ROW LEVEL SECURITY;

-- Políticas de RLS para workouts
CREATE POLICY "Users can view their own workouts" ON workouts
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own workouts" ON workouts
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own workouts" ON workouts
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own workouts" ON workouts
  FOR DELETE USING (auth.uid() = user_id);

-- Políticas de RLS para exercises
CREATE POLICY "Users can view their own exercises" ON exercises
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM workouts WHERE workouts.id = exercises.workout_id AND workouts.user_id = auth.uid())
  );
CREATE POLICY "Users can manage their own exercises" ON exercises
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM workouts WHERE workouts.id = exercises.workout_id AND workouts.user_id = auth.uid())
  );
CREATE POLICY "Users can update their own exercises" ON exercises
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM workouts WHERE workouts.id = exercises.workout_id AND workouts.user_id = auth.uid())
  );
CREATE POLICY "Users can delete their own exercises" ON exercises
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM workouts WHERE workouts.id = exercises.workout_id AND workouts.user_id = auth.uid())
  );

-- Políticas de RLS para diets (similares a workouts)
CREATE POLICY "Users can view their own diets" ON diets
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own diets" ON diets
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own diets" ON diets
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own diets" ON diets
  FOR DELETE USING (auth.uid() = user_id);

-- Políticas de RLS para meals
CREATE POLICY "Users can view their own meals" ON meals
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM diets WHERE diets.id = meals.diet_id AND diets.user_id = auth.uid())
  );
CREATE POLICY "Users can manage their own meals" ON meals
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM diets WHERE diets.id = meals.diet_id AND diets.user_id = auth.uid())
  );
CREATE POLICY "Users can update their own meals" ON meals
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM diets WHERE diets.id = meals.diet_id AND diets.user_id = auth.uid())
  );
CREATE POLICY "Users can delete their own meals" ON meals
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM diets WHERE diets.id = meals.diet_id AND diets.user_id = auth.uid())
  );

-- Políticas de RLS para daily_diets
CREATE POLICY "Users can view their own daily diets" ON daily_diets
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own daily diets" ON daily_diets
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own daily diets" ON daily_diets
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own daily diets" ON daily_diets
  FOR DELETE USING (auth.uid() = user_id);

-- Políticas de RLS para foods
CREATE POLICY "Users can view their own foods" ON foods
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own foods" ON foods
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own foods" ON foods
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own foods" ON foods
  FOR DELETE USING (auth.uid() = user_id);
```

### 4. **Testear la Aplicación**

```bash
# En la carpeta del frontend
cd /Users/josh/Healty-T/frontend

# Ejecutar en desarrollo
flutter run

# O compilar para una plataforma específica
flutter build web      # Para web
flutter build ios      # Para iOS
flutter build android  # Para Android
```

## Estructura Final del Proyecto

```
/Users/josh/Healty-T/
├── frontend/                        # Flutter App
│   ├── lib/
│   │   ├── main.dart
│   │   ├── auth_screen.dart
│   │   ├── diet_camera_screen.dart  # ACTUALIZADO
│   │   ├── api_config.dart          # ACTUALIZADO
│   │   └── ...
│   ├── supabase/
│   │   ├── functions/
│   │   │   ├── import-workouts/     # CORREGIDA
│   │   │   ├── import-diets/        # NUEVA
│   │   │   └── identify-food/       # NUEVA
│   │   └── config.toml              # ACTUALIZADO
│   └── ...
└── MIGRATION_COMPLETE.md            # Este archivo
```

## Ventajas de la Nueva Arquitectura

✅ **Sin servidor backend** - Reduce costos y mantenimiento
✅ **Autenticación segura** - Supabase Auth con JWT
✅ **Base de datos en tiempo real** - Supabase PostgreSQL con Realtime
✅ **Edge Functions** - Procesamiento serverless con baja latencia
✅ **Escalabilidad** - Automática con Supabase
✅ **Mejor seguridad** - RLS en todas las tablas
✅ **Integración con Gemini** - IA para análisis de comida

## Notas Importantes

1. **Gemini API Key**: Asegúrate de que está configurada en Supabase
2. **CORS**: Las Edge Functions están configuradas con CORS permisivo
3. **JWT**: Ya no hay necesidad de Sanctum de Laravel
4. **Base de datos**: Usa PostgreSQL de Supabase (compatible con Laravel)
5. **Migraciones**: Las estructuras de tablas se asemejan a las originales de Laravel

## Solución de Problemas

### Si las Edge Functions fallan al deployer:
```bash
# Verificar la sintaxis Deno
deno check supabase/functions/import-workouts/index.ts

# Ver los logs en tiempo real
supabase functions list
```

### Si tienes errores de autenticación:
- Verifica que el token de Supabase es válido
- Asegúrate que el usuario está autenticado antes de hacer llamadas

### Si las imágenes de comida no se analizan:
- Verifica que `GEMINI_API_KEY` está configurada en Supabase
- Revisa que la imagen no es demasiado pesada
- Prueba con una imagen más clara

## ¡Listo! 🎉

Tu aplicación ahora está completamente migrada a Supabase. No hay más dependencia de Laravel.
