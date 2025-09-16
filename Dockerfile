# Use the official DVWA base image
FROM ghcr.io/digininja/dvwa:latest

# Set working directory
WORKDIR /var/www/html

# Copy local source code to override the default DVWA files
COPY . /var/www/html/

# Ensure proper permissions
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html

# Copy configuration if it doesn't exist
RUN if [ ! -f config/config.inc.php ]; then \
      cp config/config.inc.php.dist config/config.inc.php; \
    fi

# Expose port 80
EXPOSE 80

# Health check to ensure the application is running
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/ || exit 1

# Start Apache
CMD ["apache2-foreground"]
