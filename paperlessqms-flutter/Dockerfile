# Stage 1: Build all Flutter web apps
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-build
ARG API_URL=http://localhost:8080
WORKDIR /app
COPY . .

# Install common package dependency first
RUN cd paperlessqms-common && flutter pub get

RUN cd paperlessqms-admin && flutter pub get && \
    flutter build web --release --base-href /admin/ \
    --dart-define=API_URL=${API_URL}

RUN cd paperlessqms-call && flutter pub get && \
    flutter build web --release --base-href /call/ \
    --dart-define=API_URL=${API_URL}

RUN cd paperlessqms-client && flutter pub get && \
    flutter build web --release --base-href /client/ \
    --dart-define=API_URL=${API_URL}

RUN cd paperlessqms-kiosk && flutter pub get && \
    flutter build web --release --base-href /kiosk/ \
    --dart-define=API_URL=${API_URL}

RUN cd paperlessqms-mysuper && flutter pub get && \
    flutter build web --release --base-href /super/ \
    --dart-define=API_URL=${API_URL}

# Stage 2: Serve with nginx
FROM nginx:1.25-alpine
COPY --from=flutter-build /app/paperlessqms-admin/build/web    /usr/share/nginx/html/admin
COPY --from=flutter-build /app/paperlessqms-call/build/web     /usr/share/nginx/html/call
COPY --from=flutter-build /app/paperlessqms-client/build/web   /usr/share/nginx/html/client
COPY --from=flutter-build /app/paperlessqms-kiosk/build/web    /usr/share/nginx/html/kiosk
COPY --from=flutter-build /app/paperlessqms-mysuper/build/web  /usr/share/nginx/html/super
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
